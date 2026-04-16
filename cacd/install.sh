#!/usr/bin/env bash
# cacd/install.sh — install CACD into a target repository.
#
# Usage:
#   install.sh [<repo-path>] [--force] [--quiet]
#
# Idempotent. Copies:
#   * cacd/                             (CLI + library + prompts + templates)
#   * .github/workflows/cacd.yml        (caller workflow — one line into reusable)
#   * .github/workflows/cacd-cleanup.yml
#   * .github/PULL_REQUEST_TEMPLATE.md  (only if missing)
#   * .cacd/config.yaml                 (only if missing)
#   * .cacd/repo-context.md             (only if missing)

set -euo pipefail

CACD_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-$PWD}"
force=0
quiet=0
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=1 ;;
        --quiet) quiet=1 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

log() { (( quiet == 1 )) || printf '[cacd-install] %s\n' "$*"; }

[[ -d "$target" ]] || { echo "target does not exist: $target" >&2; exit 2; }
mkdir -p "$target/.github/workflows" "$target/.cacd"

# 1. Copy the cacd/ module (always refresh — it's versioned with the tool).
#    Self-install (target/cacd == CACD_SRC) is a no-op to avoid deleting
#    our own source.
target_cacd="$target/cacd"
cacd_src_real=$(cd "$CACD_SRC" && pwd -P)
target_cacd_real=$([[ -d "$target_cacd" ]] && (cd "$target_cacd" && pwd -P) || echo "")
if [[ -n "$target_cacd_real" && "$target_cacd_real" == "$cacd_src_real" ]]; then
    log "target cacd/ is the source cacd/ — skipping self-copy"
else
    if [[ -d "$target_cacd" && $force -eq 0 ]]; then
        log "cacd/ exists, overwriting (use --force to suppress this note)"
    fi
    rm -rf "$target_cacd"
    cp -r "$CACD_SRC" "$target_cacd"
    # Strip tests/ from installed copy to keep payload small.
    rm -rf "$target_cacd/tests" 2>/dev/null || true
fi
find "$target_cacd" -type f \( -name '*.sh' -o -name 'cacd' \) -exec chmod +x {} + 2>/dev/null || true

# 2. Workflows (refresh).
cp "$CACD_SRC/templates/workflows/cacd.yml"         "$target/.github/workflows/cacd.yml"
cp "$CACD_SRC/templates/workflows/cacd-cleanup.yml" "$target/.github/workflows/cacd-cleanup.yml"

# 3. First-time-only files.
install_once() {
    local src="$1" dst="$2"
    if [[ -f "$dst" && $force -eq 0 ]]; then
        log "keeping existing $dst"
    else
        cp "$src" "$dst"
        log "installed $dst"
    fi
}
install_once "$CACD_SRC/templates/config.yaml"              "$target/.cacd/config.yaml"
install_once "$CACD_SRC/templates/repo-context.md"          "$target/.cacd/repo-context.md"
install_once "$CACD_SRC/templates/pull-request-template.md" "$target/.github/PULL_REQUEST_TEMPLATE.md"
install_once "$CACD_SRC/templates/CODEOWNERS"               "$target/.github/CODEOWNERS"

# 4. Ensure .gitignore excludes CACD run output (ensure trailing newline).
gitignore="$target/.gitignore"
touch "$gitignore"
if ! grep -q '^\.cacd/out/' "$gitignore"; then
    if [[ -s "$gitignore" ]] && [[ "$(tail -c1 "$gitignore")" != $'\n' ]]; then
        printf '\n' >> "$gitignore"
    fi
    printf '.cacd/out/\n' >> "$gitignore"
fi

log "CACD installed at $target"
log "next: commit the new files, then push a PR to exercise the pipeline."
