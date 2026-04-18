#!/usr/bin/env bash
# Gate: branch name must match configured pattern.
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

pattern=$(cicd::config checks.branch_naming.pattern '^(cursor|feature|fix|chore|docs|adr)\/[a-z0-9][a-z0-9._-]*$')
exempt_json=$(cicd::config checks.branch_naming.exempt '["main","master","develop"]')

branch="${CICD_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"

if printf '%s' "$exempt_json" | jq -e --arg b "$branch" 'any(.[]; . == $b)' >/dev/null; then
    cicd::emit check branch-naming pass "exempt branch: $branch" "$(jq -n --arg b "$branch" '{branch:$b,exempt:true}')"
    exit 0
fi

if [[ "$branch" =~ $pattern ]]; then
    cicd::emit check branch-naming pass "branch '$branch' matches '$pattern'" "$(jq -n --arg b "$branch" --arg p "$pattern" '{branch:$b,pattern:$p}')"
    exit 0
fi

cicd::emit check branch-naming fail "branch '$branch' does not match '$pattern'" \
    "$(jq -n --arg b "$branch" --arg p "$pattern" '{branch:$b,pattern:$p}')"
exit 1
