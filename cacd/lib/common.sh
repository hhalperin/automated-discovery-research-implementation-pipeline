#!/usr/bin/env bash
# cacd/lib/common.sh — shared helpers for checks, judges, and the runner.
# Source with: . "$CACD_ROOT/lib/common.sh"

set -euo pipefail

: "${CACD_ROOT:?CACD_ROOT must be set to the cacd/ module root}"
: "${CACD_REPO:=$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
: "${CACD_OUT:=$CACD_REPO/.cacd/out}"
: "${CACD_CONFIG:=$CACD_REPO/.cacd/config.yaml}"
: "${CACD_BRANCH:=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
: "${CACD_BASE_REF:=origin/main}"

mkdir -p "$CACD_OUT/checks" "$CACD_OUT/judges"

cacd::log() { printf '[cacd] %s\n' "$*" >&2; }
cacd::err() { printf '[cacd][error] %s\n' "$*" >&2; }

# Emit a structured JSON result for a check or judge.
# Usage: cacd::emit <kind> <name> <status> <summary> [json_details]
# kind in {check, judge}. status in {pass, fail, warn, skipped}.
cacd::emit() {
    local kind="$1" name="$2" status="$3" summary="$4"
    local details="${5:-null}"
    local out_dir="$CACD_OUT/${kind}s"
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

# Read a scalar from .cacd/config.yaml. Falls back to default.
# Usage: value=$(cacd::config <dotted.key> <default>)
cacd::config() {
    local key="$1" default="${2-}"
    if [[ ! -f "$CACD_CONFIG" ]]; then
        printf '%s' "$default"
        return 0
    fi
    python3 - "$CACD_CONFIG" "$key" "$default" <<'PY'
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

# Collect changed files between base and head as newline-delimited.
cacd::changed_files() {
    local base="${CACD_BASE_SHA:-}" head="${CACD_HEAD_SHA:-HEAD}"
    if [[ -z "$base" ]]; then
        base=$(git merge-base "$CACD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CACD_BASE_REF" 2>/dev/null || echo "")
    fi
    if [[ -z "$base" ]]; then
        cacd::err "cannot determine merge base; falling back to last commit"
        git diff --name-only HEAD~1..HEAD 2>/dev/null || true
        return 0
    fi
    git diff --name-only "$base..$head"
}

cacd::changed_line_stats() {
    local base="${CACD_BASE_SHA:-}" head="${CACD_HEAD_SHA:-HEAD}"
    if [[ -z "$base" ]]; then
        base=$(git merge-base "$CACD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CACD_BASE_REF" 2>/dev/null || echo "")
    fi
    if [[ -z "$base" ]]; then
        printf '0\t0\t0\n'
        return 0
    fi
    # lines added, lines removed, files changed
    git diff --numstat "$base..$head" | awk '
        BEGIN { a=0; r=0; f=0 }
        $1 == "-" || $2 == "-" { f += 1; next }
        { a += $1; r += $2; f += 1 }
        END { printf "%d\t%d\t%d\n", a, r, f }
    '
}

cacd::pr_body() {
    if [[ -n "${CACD_PR_BODY_FILE:-}" && -f "$CACD_PR_BODY_FILE" ]]; then
        cat "$CACD_PR_BODY_FILE"
    else
        printf ''
    fi
}
