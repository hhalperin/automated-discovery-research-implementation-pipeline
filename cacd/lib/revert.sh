#!/usr/bin/env bash
# cacd/lib/revert.sh — open a revert PR for a merged commit.
#
# Usage:  cacd revert <sha> [--base main] [--reason "why"]
set -euo pipefail
. "$CACD_ROOT/lib/common.sh"

sha="${1:?SHA to revert required}"; shift || true
base="main"
reason="Automated revert via CACD"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base) base="$2"; shift ;;
        --reason) reason="$2"; shift ;;
        *) cacd::err "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

git fetch origin "$base"
short=$(git rev-parse --short "$sha")
branch="cacd/revert-${short}-$(date -u +%Y%m%d%H%M%S)"

git checkout "origin/$base"
git checkout -b "$branch"

if ! git revert --no-edit "$sha"; then
    cacd::err "revert produced conflicts; aborting"
    git revert --abort || true
    exit 1
fi

git push -u origin "$branch"

if command -v gh >/dev/null 2>&1; then
    gh pr create \
        --base "$base" \
        --head "$branch" \
        --title "Revert: $short" \
        --body "$(printf 'Automated revert of %s via CACD.\n\nReason: %s\n' "$sha" "$reason")" \
        --draft || cacd::err "failed to open PR; revert branch pushed"
else
    cacd::log "revert branch pushed: $branch (gh CLI not installed — open PR manually)"
fi
