#!/usr/bin/env bash
# cacd/lib/judges/_runner.sh — shared LLM-judge driver.
#
# Usage (sourced): cacd::judge::run <judge-name> <prompt-file>
#
# Reads an agent prompt, injects diff + PR body + optional project context,
# calls the configured LLM backend, parses JSON, and emits a judge result.
#
# Backends (chosen automatically):
#   1. cursor-agent CLI  (if `cursor-agent` is on PATH) — preferred.
#   2. openai python SDK (if OPENAI_API_KEY and `openai` importable).
#   3. stub              (emits {verdict: "skipped"}).

set -euo pipefail
. "$CACD_ROOT/lib/common.sh"

cacd::judge::_collect_diff() {
    local base="${CACD_BASE_SHA:-}"
    local head="${CACD_HEAD_SHA:-HEAD}"
    if [[ -z "$base" ]]; then
        base=$(git merge-base "$CACD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CACD_BASE_REF" 2>/dev/null || echo "")
    fi
    if [[ -z "$base" ]]; then
        echo "(no merge base)"
        return 0
    fi
    # Cap diff size so judges stay cheap.
    git diff --unified=3 "$base..$head" | head -c 60000
}

cacd::judge::_collect_commits() {
    local base="${CACD_BASE_SHA:-}"
    local head="${CACD_HEAD_SHA:-HEAD}"
    if [[ -z "$base" ]]; then
        base=$(git merge-base "$CACD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CACD_BASE_REF" 2>/dev/null || echo "")
    fi
    [[ -z "$base" ]] && { echo "(no merge base)"; return 0; }
    git log --no-merges --format='- %h %s' "$base..$head"
}

cacd::judge::_backend() {
    if command -v cursor-agent >/dev/null 2>&1 && [[ -n "${CURSOR_API_KEY:-}${CURSOR_AGENTS_API_KEY:-}" ]]; then
        echo cursor-agent
    elif [[ -n "${OPENAI_API_KEY:-}" ]] && python3 -c 'import openai' >/dev/null 2>&1; then
        echo openai
    else
        echo stub
    fi
}

# Render a prompt with expansion of {{diff}}, {{commits}}, {{pr_body}}, {{repo_context}}.
cacd::judge::_render_prompt() {
    local prompt_file="$1"
    local tmp_diff tmp_commits tmp_body tmp_context
    tmp_diff=$(mktemp); tmp_commits=$(mktemp); tmp_body=$(mktemp); tmp_context=$(mktemp)
    cacd::judge::_collect_diff > "$tmp_diff"
    cacd::judge::_collect_commits > "$tmp_commits"
    cacd::pr_body > "$tmp_body"
    if [[ -f "$CACD_REPO/.cacd/repo-context.md" ]]; then
        cat "$CACD_REPO/.cacd/repo-context.md" > "$tmp_context"
    else
        printf '' > "$tmp_context"
    fi
    python3 - "$prompt_file" "$tmp_diff" "$tmp_commits" "$tmp_body" "$tmp_context" <<'PY'
import pathlib, sys
tmpl = pathlib.Path(sys.argv[1]).read_text()
fields = {
    'diff':        pathlib.Path(sys.argv[2]).read_text(),
    'commits':     pathlib.Path(sys.argv[3]).read_text(),
    'pr_body':     pathlib.Path(sys.argv[4]).read_text(),
    'repo_context':pathlib.Path(sys.argv[5]).read_text(),
}
for k, v in fields.items():
    tmpl = tmpl.replace("{{" + k + "}}", v)
print(tmpl)
PY
    rm -f "$tmp_diff" "$tmp_commits" "$tmp_body" "$tmp_context"
}

cacd::judge::_call_openai() {
    # Reads the rendered prompt from stdin.
    OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}" \
    python3 - <<'PY'
import json, os, sys
prompt = sys.stdin.read()
try:
    from openai import OpenAI
    client = OpenAI()
    resp = client.chat.completions.create(
        model=os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": "You are a strict code-review judge. Always respond with a single valid JSON object and nothing else."},
            {"role": "user", "content": prompt},
        ],
        temperature=0,
        response_format={"type": "json_object"},
    )
    print(resp.choices[0].message.content)
except Exception as e:
    print(json.dumps({"verdict": "skipped", "rationale": f"openai error: {e}", "score": None, "suggestions": []}))
PY
}

cacd::judge::_call_cursor_agent() {
    local prompt="$1"
    if ! command -v cursor-agent >/dev/null 2>&1; then
        printf '{"verdict":"skipped","rationale":"cursor-agent not installed","score":null,"suggestions":[]}'
        return 0
    fi
    # The `cursor-agent` CLI is expected to accept a one-shot prompt and return stdout.
    cursor-agent run --json --prompt "$prompt" 2>/dev/null \
        || printf '{"verdict":"skipped","rationale":"cursor-agent failed","score":null,"suggestions":[]}'
}

cacd::judge::run() {
    local name="$1" prompt_file="$2"
    local rendered
    rendered=$(cacd::judge::_render_prompt "$prompt_file")

    local backend
    backend=$(cacd::judge::_backend)
    cacd::log "judge '$name' using backend: $backend"

    local raw
    case "$backend" in
        openai)        raw=$(printf '%s' "$rendered" | cacd::judge::_call_openai) ;;
        cursor-agent)  raw=$(cacd::judge::_call_cursor_agent "$rendered") ;;
        stub|*)        raw='{"verdict":"skipped","rationale":"no LLM backend available (set OPENAI_API_KEY or install cursor-agent)","score":null,"suggestions":[]}' ;;
    esac

    local parsed
    parsed=$(printf '%s' "$raw" | python3 -c '
import json, sys
text = sys.stdin.read().strip()
start = text.find("{")
end = text.rfind("}")
if start != -1 and end != -1:
    text = text[start:end+1]
try:
    obj = json.loads(text)
except Exception as e:
    obj = {"verdict": "skipped", "rationale": f"judge returned non-JSON: {e}", "score": None, "suggestions": []}
print(json.dumps(obj))
')

    local verdict score rationale suggestions
    verdict=$(printf '%s' "$parsed" | jq -r '.verdict // "skipped"')
    score=$(printf '%s' "$parsed" | jq -r '.score // empty')
    rationale=$(printf '%s' "$parsed" | jq -r '.rationale // ""')
    suggestions=$(printf '%s' "$parsed" | jq '.suggestions // []')

    local status
    case "$verdict" in
        improvement|pass|ok|neutral) status=pass ;;
        advisory|warn|warning)       status=warn ;;
        regression|fail|blocker)     status=fail ;;
        skipped|na)                  status=skipped ;;
        *)                           status=warn ;;
    esac

    local summary="verdict=$verdict"
    [[ -n "$score" && "$score" != "null" ]] && summary+=" score=$score"
    [[ -n "$rationale" ]] && summary+=" — $(printf '%s' "$rationale" | head -c 280)"

    local details
    details=$(jq -n \
        --arg verdict "$verdict" \
        --arg score "$score" \
        --arg rationale "$rationale" \
        --argjson suggestions "$suggestions" \
        --arg backend "$backend" \
        '{verdict:$verdict, score:$score, rationale:$rationale, suggestions:$suggestions, backend:$backend}')
    cacd::emit judge "$name" "$status" "$summary" "$details"
}
