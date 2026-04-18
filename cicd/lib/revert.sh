#!/usr/bin/env bash
# cicd/lib/revert.sh — open a revert PR for a merged commit.
#
# Usage:  cicd revert <sha> [--base main] [--reason "why"]
set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

sha="${1:?SHA to revert required}"; shift || true
base="main"
reason="Automated revert via CICD"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base) base="$2"; shift ;;
        --reason) reason="$2"; shift ;;
        *) cicd::err "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

git fetch origin "$base"
short=$(git rev-parse --short "$sha")
branch="cicd/revert-${short}-$(date -u +%Y%m%d%H%M%S)"

git checkout "origin/$base"
git checkout -b "$branch"

if ! git revert --no-edit "$sha"; then
    cicd::err "revert produced conflicts; aborting"
    git revert --abort || true
    exit 1
fi

git push -u origin "$branch"

if command -v gh >/dev/null 2>&1; then
    gh pr create \
        --base "$base" \
        --head "$branch" \
        --title "Revert: $short" \
        --body "$(printf 'Automated revert of %s via CICD.\n\nReason: %s\n' "$sha" "$reason")" \
        --draft || cicd::err "failed to open PR; revert branch pushed"
else
    cicd::log "revert branch pushed: $branch (gh CLI not installed — open PR manually)"
fi
