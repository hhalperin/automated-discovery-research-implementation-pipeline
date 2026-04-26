#!/usr/bin/env bash
# Gate: if code changed, docs must change too (or be explicitly skipped).
#
# Override: add to PR body:  cicd: docs-skip <reason>
# Configure code/doc globs via .cicd/config.yaml.
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

code_patterns_json=$(cicd::config checks.doc_parity.code_patterns \
    '["\\.py$","\\.ts$","\\.tsx$","\\.js$","\\.jsx$","\\.go$","\\.rs$","\\.java$","\\.rb$","^src/","^lib/","^pkg/"]')
docs_patterns_json=$(cicd::config checks.doc_parity.docs_patterns \
    '["^docs/","^README","\\.md$","^CHANGELOG","^docs/cicd/"]')

changed=$(cicd::changed_files || true)
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

body="$(cicd::pr_body)"
override_reason=""
if grep -qE '^cicd: docs-skip' <<< "$body"; then
    override_reason=$(grep -E '^cicd: docs-skip' <<< "$body" | head -1 | sed 's/^cicd: docs-skip *//')
fi

details=$(jq -n \
    --argjson code "$code_touched" \
    --argjson docs "$docs_touched" \
    --arg override "$override_reason" \
    '{code_touched:$code,docs_touched:$docs,override_reason:$override}')

if (( code_touched == 1 && docs_touched == 0 )); then
    if [[ -n "$override_reason" ]]; then
        cicd::emit check doc-parity warn "docs untouched; override: $override_reason" "$details"
        exit 0
    fi
    cicd::emit check doc-parity fail "code changed but no docs updated (add 'cicd: docs-skip <reason>' to PR body to override)" "$details"
    exit 1
fi

cicd::emit check doc-parity pass "docs are in parity with code" "$details"
exit 0
