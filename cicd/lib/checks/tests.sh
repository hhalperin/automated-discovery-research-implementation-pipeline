#!/usr/bin/env bash
# Gate: run project test hooks declared in .cicd/config.yaml.
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

hooks_json=$(cicd::config hooks.tests '[]')
if [[ "$hooks_json" == "[]" || -z "$hooks_json" ]]; then
    cicd::emit check tests skipped "no test hooks configured" null
    exit 0
fi

mapfile -t hooks < <(printf '%s' "$hooks_json" | jq -r '.[]')

log_dir="$CICD_OUT/logs/tests"
mkdir -p "$log_dir"
failed=0
outputs=()
for i in "${!hooks[@]}"; do
    h="${hooks[$i]}"
    log="$log_dir/$i.log"
    cicd::log "test hook: $h"
    if ! bash -c "$h" >"$log" 2>&1; then
        failed=1
        outputs+=("$(jq -n --arg cmd "$h" --arg log "$(tail -c 4000 "$log")" '{cmd:$cmd,status:"fail",tail:$log}')")
    else
        outputs+=("$(jq -n --arg cmd "$h" --arg log "$(tail -c 1000 "$log")" '{cmd:$cmd,status:"pass",tail:$log}')")
    fi
done

details=$(printf '%s\n' "${outputs[@]}" | jq -s '{hooks: .}')

if (( failed == 1 )); then
    cicd::emit check tests fail "one or more test hooks failed" "$details"
    exit 1
fi
cicd::emit check tests pass "all test hooks passed" "$details"
exit 0
