#!/usr/bin/env bash
# Gate: bounded diff size so PRs stay reviewable and easily revertable.
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"

max_lines=$(cacd::config checks.size_cap.max_changed_lines 800)
max_files=$(cacd::config checks.size_cap.max_changed_files 50)

read -r added removed files < <(cacd::changed_line_stats)
total=$(( added + removed ))

details=$(jq -n \
    --argjson added "$added" --argjson removed "$removed" \
    --argjson files "$files" --argjson total "$total" \
    --argjson max_lines "$max_lines" --argjson max_files "$max_files" \
    '{added:$added,removed:$removed,files:$files,total:$total,limits:{lines:$max_lines,files:$max_files}}')

if (( total > max_lines || files > max_files )); then
    cacd::emit check size-cap fail "diff too large: +${added}/-${removed} lines across ${files} files (caps: ${max_lines} lines / ${max_files} files)" "$details"
    exit 1
fi

cacd::emit check size-cap pass "diff ${total} lines across ${files} files (within caps)" "$details"
exit 0
