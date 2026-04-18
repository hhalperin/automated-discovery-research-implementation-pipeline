#!/usr/bin/env bash
# cicd/lib/judges/_runner.sh — shared LLM-judge driver.
#
# Usage (sourced): cicd::judge::run <judge-name> <prompt-file>
#
# Reads an agent prompt, injects diff + PR body + optional project context,
# calls the configured LLM backend, parses JSON, and emits a judge result.
#
# Backends (chosen automatically):
#   1. cursor-agent CLI  (if `cursor-agent` is on PATH) — preferred.
#   2. openai python SDK (if OPENAI_API_KEY and `openai` importable).
#   3. stub              (emits {verdict: "skipped"}).

set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

cicd::judge::_collect_diff() {
    local base head
    IFS=$'\t' read -r base head < <(cicd::_resolve_refs)
    if [[ -z "$base" ]]; then
        echo "(no merge base)"
        return 0
    fi
    # Cap diff size so judges stay cheap.
    git diff --unified=3 "$base..$head" 2>/dev/null | head -c 60000
}

cicd::judge::_collect_commits() {
    local base head
    IFS=$'\t' read -r base head < <(cicd::_resolve_refs)
    [[ -z "$base" ]] && { echo "(no merge base)"; return 0; }
    git log --no-merges --format='- %h %s' "$base..$head" 2>/dev/null || true
}

# Resolve the path to the Cursor CLI binary.
# Cursor renamed `cursor-agent` to plain `agent` (installed under
# ~/.local/bin or ~/.cursor/bin by `curl https://cursor.com/install | bash`).
# We accept either, in this priority: PATH `agent`, PATH `cursor-agent`,
# `~/.cursor/bin/agent`, `~/.local/bin/agent`.
cicd::judge::_cursor_bin() {
    if command -v agent >/dev/null 2>&1; then
        command -v agent
        return 0
    fi
    if command -v cursor-agent >/dev/null 2>&1; then
        command -v cursor-agent
        return 0
    fi
    for cand in "$HOME/.cursor/bin/agent" "$HOME/.local/bin/agent"; do
        [[ -x "$cand" ]] && { printf '%s' "$cand"; return 0; }
    done
    return 1
}

cicd::judge::_backend() {
    # Override with CICD_JUDGE_BACKEND=cursor-agent|anthropic|openai|stub.
    case "${CICD_JUDGE_BACKEND:-}" in
        cursor-agent|anthropic|openai|stub)
            echo "${CICD_JUDGE_BACKEND}"; return 0 ;;
    esac
    if cicd::judge::_cursor_bin >/dev/null 2>&1 && [[ -n "${CURSOR_API_KEY:-}${CURSOR_AGENTS_API_KEY:-}" ]]; then
        echo cursor-agent
    elif [[ -n "${ANTHROPIC_API_KEY:-}" ]] && python3 -c 'import anthropic' >/dev/null 2>&1; then
        echo anthropic
    elif [[ -n "${OPENAI_API_KEY:-}" ]] && python3 -c 'import openai' >/dev/null 2>&1; then
        echo openai
    else
        echo stub
    fi
}

# Render a prompt with expansion of {{diff}}, {{commits}}, {{pr_body}}, {{repo_context}}.
cicd::judge::_render_prompt() {
    local prompt_file="$1"
    local tmp_diff tmp_commits tmp_body tmp_context
    tmp_diff=$(mktemp); tmp_commits=$(mktemp); tmp_body=$(mktemp); tmp_context=$(mktemp)
    cicd::judge::_collect_diff > "$tmp_diff"
    cicd::judge::_collect_commits > "$tmp_commits"
    cicd::pr_body > "$tmp_body"
    if [[ -f "$CICD_REPO/.cicd/repo-context.md" ]]; then
        cat "$CICD_REPO/.cicd/repo-context.md" > "$tmp_context"
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

cicd::judge::_call_openai() {
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

cicd::judge::_call_anthropic() {
    # Reads the rendered prompt from stdin.
    ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-${CICD_ANTHROPIC_MODEL:-claude-sonnet-4-5-20250929}}" \
    python3 - <<'PY'
import json, os, sys
prompt = sys.stdin.read()
try:
    from anthropic import Anthropic
    client = Anthropic()
    resp = client.messages.create(
        model=os.environ.get("ANTHROPIC_MODEL"),
        max_tokens=1024,
        temperature=0,
        system=("You are a strict code-review judge. Respond with a single "
                "valid JSON object and nothing else — no prose, no code "
                "fences, just the JSON."),
        messages=[{"role": "user", "content": prompt}],
    )
    # The response is a list of content blocks; take the first text block.
    text = ""
    for block in resp.content:
        if getattr(block, "type", "") == "text":
            text = block.text
            break
    print(text or json.dumps({"verdict":"skipped","rationale":"empty anthropic response","score":None,"suggestions":[]}))
except Exception as e:
    print(json.dumps({"verdict":"skipped","rationale":f"anthropic error: {e}","score":None,"suggestions":[]}))
PY
}

cicd::judge::_call_cursor_agent() {
    local prompt="$1"
    local bin
    if ! bin=$(cicd::judge::_cursor_bin); then
        printf '{"verdict":"skipped","rationale":"Cursor CLI not installed (run cicd install-agent)","score":null,"suggestions":[]}'
        return 0
    fi
    # The Cursor CLI exposes a non-interactive `print` mode via -p / --print.
    # We force JSON output so the judge prompt's required object format is
    # preserved through the model response. CURSOR_API_KEY is supplied via env.
    local model="${CICD_CURSOR_MODEL:-}"
    local args=(-p "$prompt" --output-format json)
    [[ -n "$model" ]] && args+=(--model "$model")
    "$bin" "${args[@]}" 2>/dev/null \
        || printf '{"verdict":"skipped","rationale":"Cursor CLI invocation failed","score":null,"suggestions":[]}'
}

cicd::judge::run() {
    local name="$1" prompt_file="$2"
    local rendered
    rendered=$(cicd::judge::_render_prompt "$prompt_file")

    local backend
    backend=$(cicd::judge::_backend)
    cicd::log "judge '$name' using backend: $backend"

    local raw
    # Write the rendered prompt to a temp file so backends can re-read it
    # without risking SIGPIPE on long diffs (~60KB).
    local prompt_tmp
    prompt_tmp=$(mktemp)
    printf '%s' "$rendered" > "$prompt_tmp"

    case "$backend" in
        openai)        raw=$(cicd::judge::_call_openai    < "$prompt_tmp") ;;
        anthropic)     raw=$(cicd::judge::_call_anthropic < "$prompt_tmp") ;;
        cursor-agent)  raw=$(cicd::judge::_call_cursor_agent "$rendered") ;;
        stub|*)        raw='{"verdict":"skipped","rationale":"no LLM backend available (set ANTHROPIC_API_KEY or OPENAI_API_KEY, or install Cursor CLI with `cicd install-agent` and set CURSOR_API_KEY)","score":null,"suggestions":[]}' ;;
    esac
    rm -f "$prompt_tmp"

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
    cicd::emit judge "$name" "$status" "$summary" "$details"
}
