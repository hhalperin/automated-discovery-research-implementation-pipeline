#!/usr/bin/env bash
# Gate: scan the diff for probable secrets.
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

base="${CICD_BASE_SHA:-}"
head="${CICD_HEAD_SHA:-HEAD}"
if [[ -z "$base" ]]; then
    base=$(git merge-base "$CICD_BASE_REF" "$head" 2>/dev/null || git rev-parse "$CICD_BASE_REF" 2>/dev/null || echo "")
fi

if [[ -z "$base" ]]; then
    cicd::emit check secrets skipped "cannot determine merge base" null
    exit 0
fi

patterns=(
    'AKIA[0-9A-Z]{16}'                 # AWS access key id
    'aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{20,}'
    'ghp_[A-Za-z0-9]{30,}'             # GitHub PAT
    'github_pat_[A-Za-z0-9_]{20,}'     # Fine-grained PAT
    'xox[baprs]-[A-Za-z0-9-]{10,}'     # Slack
    'sk-[A-Za-z0-9]{20,}'              # OpenAI-shape
    '-----BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY-----'
    'AIza[0-9A-Za-z\-_]{35}'           # Google API
)

# Build a combined regex.
joined=""
for p in "${patterns[@]}"; do
    [[ -n "$joined" ]] && joined+="|"
    joined+="(${p})"
done

# Limit to added lines; ignore .cicd/lib/checks/secrets.sh itself and any
# patterns-only file. Also ignore files matched by .cicd/secrets-allowlist.
allowlist_file="$CICD_REPO/.cicd/secrets-allowlist"

tmp=$(mktemp)
git diff --unified=0 "$base..$head" -- . ':(exclude)cicd/lib/checks/secrets.sh' ':(exclude).cicd/out/**' \
    | grep -E '^\+' \
    | grep -vE '^\+\+\+' \
    | grep -Ev 'cicd: secret-allow' \
    > "$tmp" || true

matches=""
if [[ -s "$tmp" ]]; then
    matches=$(grep -EI "$joined" "$tmp" || true)
fi

if [[ -f "$allowlist_file" && -n "$matches" ]]; then
    # Drop any line matching an allowlist regex.
    while IFS= read -r allow; do
        [[ -z "$allow" || "$allow" =~ ^# ]] && continue
        matches=$(printf '%s\n' "$matches" | grep -Ev "$allow" || true)
    done < "$allowlist_file"
fi

if [[ -n "$matches" ]]; then
    count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
    details=$(jq -n --arg sample "$(printf '%s\n' "$matches" | head -5)" --argjson count "$count" \
        '{count:$count, sample:$sample}')
    cicd::emit check secrets fail "possible secrets detected in $count added line(s)" "$details"
    rm -f "$tmp"
    exit 1
fi

rm -f "$tmp"
cicd::emit check secrets pass "no probable secrets in diff" null
exit 0
