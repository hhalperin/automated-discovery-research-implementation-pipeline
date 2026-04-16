#!/usr/bin/env bash
# Gate: if code changed, docs must change too (or be explicitly skipped).
#
# Override: add to PR body:  cacd: docs-skip <reason>
# Configure code/doc globs via .cacd/config.yaml.
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"

code_patterns_json=$(cacd::config checks.doc_parity.code_patterns \
    '["\\.py$","\\.ts$","\\.tsx$","\\.js$","\\.jsx$","\\.go$","\\.rs$","\\.java$","\\.rb$","^src/","^lib/","^pkg/"]')
docs_patterns_json=$(cacd::config checks.doc_parity.docs_patterns \
    '["^docs/","^README","\\.md$","^CHANGELOG","^docs/cacd/"]')

changed=$(cacd::changed_files || true)
match_any() {
    local file="$1" patterns_json="$2"
    printf '%s' "$patterns_json" | jq -r '.[]' | while IFS= read -r pat; do
        if [[ "$file" =~ $pat ]]; then
            echo match
            return
        fi
    done
}

code_touched=0
docs_touched=0
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ -n "$(match_any "$f" "$code_patterns_json")" ]]; then
        code_touched=1
    fi
    if [[ -n "$(match_any "$f" "$docs_patterns_json")" ]]; then
        docs_touched=1
    fi
done <<< "$changed"

body="$(cacd::pr_body)"
override_reason=""
if grep -qE '^cacd: docs-skip' <<< "$body"; then
    override_reason=$(grep -E '^cacd: docs-skip' <<< "$body" | head -1 | sed 's/^cacd: docs-skip *//')
fi

details=$(jq -n \
    --argjson code "$code_touched" \
    --argjson docs "$docs_touched" \
    --arg override "$override_reason" \
    '{code_touched:$code,docs_touched:$docs,override_reason:$override}')

if (( code_touched == 1 && docs_touched == 0 )); then
    if [[ -n "$override_reason" ]]; then
        cacd::emit check doc-parity warn "docs untouched; override: $override_reason" "$details"
        exit 0
    fi
    cacd::emit check doc-parity fail "code changed but no docs updated (add 'cacd: docs-skip <reason>' to PR body to override)" "$details"
    exit 1
fi

cacd::emit check doc-parity pass "docs are in parity with code" "$details"
exit 0
