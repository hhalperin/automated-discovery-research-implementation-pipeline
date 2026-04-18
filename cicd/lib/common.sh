#!/usr/bin/env bash
# cicd/lib/common.sh — shared helpers for checks, judges, and the runner.
# Source with: . "$CICD_ROOT/lib/common.sh"

set -euo pipefail

: "${CICD_ROOT:?CICD_ROOT must be set to the cicd/ module root}"
: "${CICD_REPO:=$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
: "${CICD_OUT:=$CICD_REPO/.cicd/out}"
: "${CICD_CONFIG:=$CICD_REPO/.cicd/config.yaml}"
: "${CICD_BRANCH:=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
: "${CICD_BASE_REF:=origin/main}"

mkdir -p "$CICD_OUT/checks" "$CICD_OUT/judges"

cicd::log() { printf '[cicd] %s\n' "$*" >&2; }
cicd::err() { printf '[cicd][error] %s\n' "$*" >&2; }

# Emit a structured JSON result for a check or judge.
# Usage: cicd::emit <kind> <name> <status> <summary> [json_details]
# kind in {check, judge}. status in {pass, fail, warn, skipped}.
cicd::emit() {
    local kind="$1" name="$2" status="$3" summary="$4"
    local details="${5:-null}"
    local out_dir="$CICD_OUT/${kind}s"
    mkdir -p "$out_dir"
    jq -n \
        --arg kind "$kind" \
        --arg name "$name" \
        --arg status "$status" \
        --arg summary "$summary" \
        --argjson details "$details" \
        '{kind:$kind,name:$name,status:$status,summary:$summary,details:$details}' \
        > "$out_dir/$name.json"
}

# Read a scalar from .cicd/config.yaml. Falls back to default.
# Usage: value=$(cicd::config <dotted.key> <default>)
cicd::config() {
    local key="$1" default="${2-}"
    if [[ ! -f "$CICD_CONFIG" ]]; then
        printf '%s' "$default"
        return 0
    fi
    python3 - "$CICD_CONFIG" "$key" "$default" <<'PY'
import sys, pathlib
try:
    import yaml
except Exception:
    yaml = None

path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
text = pathlib.Path(path).read_text()
if yaml is not None:
    data = yaml.safe_load(text) or {}
else:
    # Very small fallback: flat `key: value` only. Users are expected to have PyYAML.
    for line in text.splitlines():
        line = line.split("#", 1)[0].rstrip()
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            data[k.strip()] = v.strip().strip('"').strip("'")
cur = data
for part in key.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None
        break
if cur is None:
    print(default, end="")
elif isinstance(cur, (dict, list)):
    import json
    print(json.dumps(cur), end="")
elif isinstance(cur, bool):
    print("true" if cur else "false", end="")
else:
    print(cur, end="")
PY
}

# Resolve (base, head) refs that are guaranteed to exist in *this* repo.
# Robust against env-var leakage from a parent cicd invocation that runs
# inside a different repo (the test hook is the canonical case).
cicd::_resolve_refs() {
    local head="${CICD_HEAD_SHA:-HEAD}"
    git rev-parse --verify "$head^{commit}" >/dev/null 2>&1 || head="HEAD"
    local base="${CICD_BASE_SHA:-}"
    if [[ -n "$base" ]] && ! git rev-parse --verify "$base^{commit}" >/dev/null 2>&1; then
        base=""
    fi
    if [[ -z "$base" ]]; then
        base=$(git merge-base "$CICD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CICD_BASE_REF" 2>/dev/null || echo "")
    fi
    printf '%s\t%s\n' "$base" "$head"
}

# Collect changed files between base and head as newline-delimited.
cicd::changed_files() {
    local base head
    IFS=$'\t' read -r base head < <(cicd::_resolve_refs)
    if [[ -z "$base" ]]; then
        cicd::err "cannot determine merge base; falling back to last commit"
        git diff --name-only HEAD~1..HEAD 2>/dev/null || true
        return 0
    fi
    git diff --name-only "$base..$head" 2>/dev/null || true
}

cicd::changed_line_stats() {
    local base head
    IFS=$'\t' read -r base head < <(cicd::_resolve_refs)
    if [[ -z "$base" ]]; then
        printf '0\t0\t0\n'
        return 0
    fi
    # lines added, lines removed, files changed
    git diff --numstat "$base..$head" 2>/dev/null | awk '
        BEGIN { a=0; r=0; f=0 }
        $1 == "-" || $2 == "-" { f += 1; next }
        { a += $1; r += $2; f += 1 }
        END { printf "%d\t%d\t%d\n", a, r, f }
    '
}

cicd::pr_body() {
    if [[ -n "${CICD_PR_BODY_FILE:-}" && -f "$CICD_PR_BODY_FILE" ]]; then
        cat "$CICD_PR_BODY_FILE"
    else
        printf ''
    fi
}
