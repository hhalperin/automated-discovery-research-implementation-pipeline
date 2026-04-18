#!/usr/bin/env bash
# cicd/lib/run.sh — run all enabled checks + judges, then aggregate.
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

only_check=""
only_judge=""
skip_judges=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check=*) only_check="${1#*=}" ;;
        --judge=*) only_judge="${1#*=}" ;;
        --no-judges) skip_judges=1 ;;
        *) cicd::err "unknown run flag: $1"; exit 2 ;;
    esac
    shift
done

# Purge previous run outputs so a re-run is deterministic.
rm -rf "$CICD_OUT"
mkdir -p "$CICD_OUT/checks" "$CICD_OUT/judges"

enabled_checks_json=$(cicd::config checks.enabled '["branch-naming","size-cap","revertability","secrets","doc-parity","lint","tests"]')
enabled_judges_json=$(cicd::config judges.enabled '["improvement","quality","docs-accuracy"]')

mapfile -t enabled_checks < <(printf '%s' "$enabled_checks_json" | jq -r '.[]')
mapfile -t enabled_judges < <(printf '%s' "$enabled_judges_json" | jq -r '.[]')

any_fail=0

for name in "${enabled_checks[@]}"; do
    [[ -n "$only_check" && "$only_check" != "$name" ]] && continue
    script="$CICD_ROOT/lib/checks/$name.sh"
    if [[ ! -x "$script" ]]; then
        cicd::err "check '$name' missing at $script"
        cicd::emit check "$name" fail "check script missing" null
        any_fail=1
        continue
    fi
    cicd::log "running check: $name"
    if ! "$script"; then
        any_fail=1
    fi
done

if [[ $skip_judges -eq 0 ]]; then
    for name in "${enabled_judges[@]}"; do
        [[ -n "$only_judge" && "$only_judge" != "$name" ]] && continue
        script="$CICD_ROOT/lib/judges/$name.sh"
        if [[ ! -x "$script" ]]; then
            cicd::err "judge '$name' missing at $script"
            cicd::emit judge "$name" skipped "judge script missing" null
            continue
        fi
        cicd::log "running judge: $name"
        # Judges never block the run; they record verdicts only.
        "$script" || cicd::err "judge '$name' errored (non-blocking)"
    done
fi

"$CICD_ROOT/lib/report.sh"

if [[ $any_fail -ne 0 ]]; then
    # Check if any blocking judges have a 'regression' verdict.
    :
fi

# Allow judges to be promoted to blocking via config.
blocking_judges_json=$(cicd::config judges.blocking '[]')
mapfile -t blocking_judges < <(printf '%s' "$blocking_judges_json" | jq -r '.[]')
for j in "${blocking_judges[@]}"; do
    verdict=$(jq -r '.verdict // "skipped"' "$CICD_OUT/judges/$j.json" 2>/dev/null || echo skipped)
    if [[ "$verdict" == "regression" || "$verdict" == "fail" ]]; then
        cicd::err "blocking judge '$j' verdict: $verdict"
        any_fail=1
    fi
done

exit $any_fail
