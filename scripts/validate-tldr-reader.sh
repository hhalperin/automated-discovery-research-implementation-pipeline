#!/usr/bin/env sh
# TLDR Reader automation — static validation (shell only, no network).
# Exits 0 if all checks pass; non-zero with FAIL lines on stderr.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEAN=".cursor/automations/tldr-reader-ultra-lean"
SPEC="$ROOT/$LEAN/automation-spec.yaml"
README="$ROOT/$LEAN/README.md"
PROMPT="$ROOT/$LEAN/prompt.md"
PROBE="$ROOT/$LEAN/prompt.probe.md"
WORKFLOW="$ROOT/.github/workflows/tldr-reader-daily.yml"

fail_count=0

fail() {
  file="$1"
  reason="$2"
  fix="$3"
  fail_count=$((fail_count + 1))
  echo "FAIL: $file: $reason" >&2
  echo "fix: $fix" >&2
}

need_file() {
  path="$1"
  if [ ! -f "$path" ]; then
    fail "$path" "missing file" "restore file or fix path reference"
    return 1
  fi
  return 0
}

grep_or_fail() {
  file="$1"
  pattern="$2"
  hint="$3"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    fail "$file" "expected pattern not found: $pattern" "$hint"
    return 1
  fi
  return 0
}

# --- Presence
need_file "$SPEC" || true
need_file "$README" || true
need_file "$PROMPT" || true
need_file "$PROBE" || true
need_file "$WORKFLOW" || true

# --- Prompt markers (production final report)
if [ -f "$PROMPT" ]; then
  grep_or_fail "$PROMPT" "BEGIN PRODUCTION FINAL REPORT JSON" "ensure prompt.md defines final JSON block markers" || true
  grep_or_fail "$PROMPT" "END PRODUCTION FINAL REPORT JSON" "ensure prompt.md closes final JSON block" || true
  grep_or_fail "$PROMPT" "STEP 0" "ensure STEP 0 startup checks exist in prompt.md" || true
fi

# --- Probe markers
if [ -f "$PROBE" ]; then
  grep_or_fail "$PROBE" "BEGIN PROBE REPORT JSON" "ensure prompt.probe.md defines probe JSON markers" || true
  grep_or_fail "$PROBE" "END PROBE REPORT JSON" "ensure prompt.probe.md closes probe JSON block" || true
fi

# --- automation-spec: keys
if [ -f "$SPEC" ]; then
  grep_or_fail "$SPEC" "^repo:" "add repo: block with url and ref" || true
  grep_or_fail "$SPEC" "^prompt_file:" "add prompt_file key" || true
  grep_or_fail "$SPEC" "^prompt_probe_file:" "add prompt_probe_file key" || true
  grep_or_fail "$SPEC" "^caveats:" "add caveats list" || true
fi

# --- Memory paths from spec exist on disk (lines under memory_paths: ending in .yaml)
if [ -f "$SPEC" ]; then
  mp_block=$(awk '/^memory_paths:/{p=1;next} p && /^[a-z_]+:/ && $0 !~ /^[[:space:]]/{exit} p' "$SPEC")
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *:*.yaml*)
        val=${line#*:}
        val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
        if [ -z "$val" ]; then
          continue
        fi
        if [ ! -f "$ROOT/$val" ]; then
          fail "$SPEC" "memory_paths points to missing file: $val" "create file or fix path in automation-spec.yaml"
        fi
        ;;
    esac
  done <<EOF
$mp_block
EOF
fi

# --- README cross-check: cron string matches spec (same literal)
if [ -f "$SPEC" ] && [ -f "$README" ]; then
  cron_line=$(grep -E '^[[:space:]]+cron:' "$SPEC" | head -1 | sed 's/.*cron:[[:space:]]*//;s/"//g' | tr -d "'")
  if [ -n "$cron_line" ] && ! grep -qF "$cron_line" "$README" 2>/dev/null; then
    fail "$README" "cron from automation-spec not echoed in README ($cron_line)" "update README Scheduling to match spec cron"
  fi
fi

# --- Workflow references prompt path and cron
if [ -f "$WORKFLOW" ]; then
  grep_or_fail "$WORKFLOW" "tldr-reader-ultra-lean/prompt.md" "workflow should pass production prompt path" || true
  grep_or_fail "$WORKFLOW" "cron:" "workflow should define schedule cron" || true
fi

if [ "$fail_count" -gt 0 ]; then
  echo "validate-tldr-reader: $fail_count check(s) failed" >&2
  exit 1
fi

echo "validate-tldr-reader: OK"
exit 0
