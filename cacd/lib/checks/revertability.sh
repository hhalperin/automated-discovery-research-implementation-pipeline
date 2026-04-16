#!/usr/bin/env bash
# Gate: the PR must be safe to revert as a single operation.
#
# A PR is considered "revertable" when:
#   * it has <= max_commits commits (default 20)
#   * vendored / generated / lock paths are not mixed with source changes,
#     unless the PR body contains `cacd: allow-mixed <reason>`
#   * it touches at most one "intent zone" (source | docs | infra) unless
#     the PR body explicitly opts in
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"

max_commits=$(cacd::config checks.revertability.max_commits 20)
vendored_patterns_json=$(cacd::config checks.revertability.vendored_patterns \
    '["^vendor/","/vendor/","^node_modules/","/node_modules/","package-lock.json$","yarn.lock$","poetry.lock$","Pipfile.lock$","go.sum$"]')
infra_patterns_json=$(cacd::config checks.revertability.infra_patterns \
    '["^\\.github/","^\\.cacd/","^infra/","^terraform/","^deploy/","Dockerfile$","docker-compose.ya?ml$"]')
docs_patterns_json=$(cacd::config checks.revertability.docs_patterns '["^docs/","^README","\\.md$"]')

base="${CACD_BASE_SHA:-}"
head="${CACD_HEAD_SHA:-HEAD}"
if [[ -z "$base" ]]; then
    base=$(git merge-base "$CACD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CACD_BASE_REF" 2>/dev/null || echo "")
fi

commits=0
if [[ -n "$base" ]]; then
    commits=$(git rev-list --count "$base..$head")
fi

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

has_vendored=0; has_source=0; has_infra=0; has_docs=0
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ -n "$(match_any "$f" "$vendored_patterns_json")" ]]; then
        has_vendored=1
        continue
    fi
    if [[ -n "$(match_any "$f" "$infra_patterns_json")" ]]; then
        has_infra=1
        continue
    fi
    if [[ -n "$(match_any "$f" "$docs_patterns_json")" ]]; then
        has_docs=1
        continue
    fi
    has_source=1
done <<< "$changed"

body="$(cacd::pr_body)"
mixed_ok=0
grep -qE '^cacd: allow-mixed' <<< "$body" && mixed_ok=1

reasons=()
if (( commits > max_commits )); then
    reasons+=("too many commits: $commits > $max_commits")
fi
if [[ $has_vendored -eq 1 && $has_source -eq 1 && $mixed_ok -eq 0 ]]; then
    reasons+=("source + vendored/lockfiles mixed (add 'cacd: allow-mixed <reason>' to PR body to override)")
fi

# Intent mixing: source + docs is *encouraged* (doc-parity requires it).
# Problematic combinations are any touch of `infra` (workflows, IaC, Dockerfiles,
# CACD itself) mixed with source/docs, because those are typically independently
# revertable concerns. Infra-only PRs are fine.
if (( has_infra == 1 && ( has_source == 1 || has_docs == 1 ) && mixed_ok == 0 )); then
    reasons+=("infra changes mixed with source/docs; split PR or add 'cacd: allow-mixed <reason>'")
fi

details=$(jq -n \
    --argjson commits "$commits" \
    --argjson max_commits "$max_commits" \
    --argjson has_vendored "$has_vendored" \
    --argjson has_source "$has_source" \
    --argjson has_infra "$has_infra" \
    --argjson has_docs "$has_docs" \
    --argjson mixed_ok "$mixed_ok" \
    '{commits:$commits,max_commits:$max_commits,zones:{source:$has_source,infra:$has_infra,docs:$has_docs,vendored:$has_vendored},mixed_override:$mixed_ok}')

if (( ${#reasons[@]} > 0 )); then
    cacd::emit check revertability fail "$(IFS='; '; echo "${reasons[*]}")" "$details"
    exit 1
fi

cacd::emit check revertability pass "PR is cleanly revertable (${commits} commits, single intent)" "$details"
exit 0
