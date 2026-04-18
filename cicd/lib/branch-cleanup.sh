#!/usr/bin/env bash
# cicd/lib/branch-cleanup.sh — prune merged remote branches, label stale PRs.
#
# Env:
#   CICD_REPO_SLUG   owner/name (auto-detected from git origin if unset)
#   CICD_STALE_DAYS  default 14
#   GH_TOKEN         GitHub token with repo scope (write for deletions)
#
# Usage:
#   cicd cleanup-branches [--dry-run] [--stale-days N] [--protect main,dev]
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

dry_run=0
stale_days="${CICD_STALE_DAYS:-14}"
protect_json=$(cicd::config branch_cleanup.protect '["main","master","develop","release"]')
prefix_allow_json=$(cicd::config branch_cleanup.prefix_allowlist '["cursor/","feature/","fix/","chore/","docs/","adr/"]')

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --stale-days) stale_days="$2"; shift ;;
        --protect) protect_json=$(jq -c 'split(",")' <<<"\"$2\""); shift ;;
        *) cicd::err "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

slug="${CICD_REPO_SLUG:-}"
if [[ -z "$slug" ]]; then
    origin=$(git remote get-url origin 2>/dev/null || echo "")
    slug=$(printf '%s' "$origin" \
        | sed -E 's#^(git@|https?://)##' \
        | sed -E 's#^[^@/]+@##' \
        | sed -E 's#^[^:/]+[:/]+##' \
        | sed -E 's#\.git$##')
fi

if [[ -z "$slug" ]]; then
    cicd::err "cannot determine repo slug; set CICD_REPO_SLUG"
    exit 2
fi

cicd::log "repo=$slug stale_days=$stale_days dry_run=$dry_run"

if ! command -v gh >/dev/null 2>&1; then
    cicd::err "gh CLI not found; cannot prune branches"
    exit 2
fi

# List remote branches + their last commit date.
tmp=$(mktemp)
gh api --paginate "repos/$slug/branches?per_page=100" > "$tmp"

now_epoch=$(date -u +%s)
threshold=$(( now_epoch - stale_days * 86400 ))

deleted=(); labeled=()
while IFS=$'\t' read -r name sha; do
    [[ -z "$name" ]] && continue
    # Protect configured branches.
    if jq -e --arg n "$name" 'any(.[]; . == $n)' <<<"$protect_json" >/dev/null; then
        continue
    fi
    # Must be on the allowlist prefix.
    if ! jq -e --arg n "$name" 'any(.[]; . as $p | ($n | startswith($p)))' <<<"$prefix_allow_json" >/dev/null; then
        continue
    fi

    commit_date=$(gh api "repos/$slug/commits/$sha" --jq '.commit.committer.date' 2>/dev/null || echo "")
    [[ -z "$commit_date" ]] && continue
    commit_epoch=$(date -u -d "$commit_date" +%s 2>/dev/null || echo 0)
    [[ "$commit_epoch" -lt "$threshold" ]] || continue

    # Is it merged into default branch?
    default_branch=$(gh api "repos/$slug" --jq '.default_branch' 2>/dev/null || echo main)
    merged=$(gh api "repos/$slug/compare/$default_branch...$name" --jq '.ahead_by' 2>/dev/null || echo "")

    if [[ "$merged" == "0" ]]; then
        # Fully merged -> delete.
        if (( dry_run == 1 )); then
            cicd::log "[dry-run] would delete merged stale branch: $name"
        else
            cicd::log "deleting merged stale branch: $name"
            gh api -X DELETE "repos/$slug/git/refs/heads/$name" >/dev/null || cicd::err "failed to delete $name"
        fi
        deleted+=("$name")
    else
        # Not merged but stale -> label any associated PR.
        pr_number=$(gh pr list --repo "$slug" --head "$name" --state open --json number --jq '.[0].number' 2>/dev/null || echo "")
        if [[ -n "$pr_number" ]]; then
            if (( dry_run == 1 )); then
                cicd::log "[dry-run] would label PR #$pr_number (branch $name) as cicd/stale"
            else
                gh pr edit "$pr_number" --repo "$slug" --add-label "cicd/stale" >/dev/null || true
            fi
            labeled+=("$name#$pr_number")
        fi
    fi
done < <(jq -r '.[] | [.name, .commit.sha] | @tsv' "$tmp")

rm -f "$tmp"

cicd::log "deleted: ${#deleted[@]}; labeled stale: ${#labeled[@]}"
