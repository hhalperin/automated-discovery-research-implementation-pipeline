#!/usr/bin/env bash
# cicd/install.sh — install CICD into a target repository.
#
# Usage:
#   install.sh [<repo-path>] [--force] [--quiet]
#
# Idempotent. Copies:
#   * cicd/                             (CLI + library + prompts + templates)
#   * .github/workflows/cicd.yml        (caller workflow — one line into reusable)
#   * .github/workflows/cicd-cleanup.yml
#   * .github/PULL_REQUEST_TEMPLATE.md  (only if missing)
#   * .cicd/config.yaml                 (only if missing)
#   * .cicd/repo-context.md             (only if missing)

set -euo pipefail

CICD_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

log() { (( quiet == 1 )) || printf '[cicd-install] %s\n' "$*"; }

[[ -d "$target" ]] || { echo "target does not exist: $target" >&2; exit 2; }
mkdir -p "$target/.github/workflows" "$target/.cicd"

# 1. Copy the cicd/ module (always refresh — it's versioned with the tool).
#    Self-install (target/cicd == CICD_SRC) is a no-op to avoid deleting
#    our own source.
target_cicd="$target/cicd"
cicd_src_real=$(cd "$CICD_SRC" && pwd -P)
target_cicd_real=$([[ -d "$target_cicd" ]] && (cd "$target_cicd" && pwd -P) || echo "")
if [[ -n "$target_cicd_real" && "$target_cicd_real" == "$cicd_src_real" ]]; then
    log "target cicd/ is the source cicd/ — skipping self-copy"
else
    if [[ -d "$target_cicd" && $force -eq 0 ]]; then
        log "cicd/ exists, overwriting (use --force to suppress this note)"
    fi
    rm -rf "$target_cicd"
    cp -r "$CICD_SRC" "$target_cicd"
    # Strip tests/ from installed copy to keep payload small.
    rm -rf "$target_cicd/tests" 2>/dev/null || true
fi
find "$target_cicd" -type f \( -name '*.sh' -o -name 'cicd' \) -exec chmod +x {} + 2>/dev/null || true

# 2. Workflows (refresh).
cp "$CICD_SRC/templates/workflows/cicd.yml"         "$target/.github/workflows/cicd.yml"
cp "$CICD_SRC/templates/workflows/cicd-cleanup.yml" "$target/.github/workflows/cicd-cleanup.yml"

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
install_once "$CICD_SRC/templates/config.yaml"              "$target/.cicd/config.yaml"
install_once "$CICD_SRC/templates/repo-context.md"          "$target/.cicd/repo-context.md"
install_once "$CICD_SRC/templates/pull-request-template.md" "$target/.github/PULL_REQUEST_TEMPLATE.md"
install_once "$CICD_SRC/templates/CODEOWNERS"               "$target/.github/CODEOWNERS"

# 4. Ensure .gitignore excludes CICD run output (ensure trailing newline).
gitignore="$target/.gitignore"
touch "$gitignore"
if ! grep -q '^\.cicd/out/' "$gitignore"; then
    if [[ -s "$gitignore" ]] && [[ "$(tail -c1 "$gitignore")" != $'\n' ]]; then
        printf '\n' >> "$gitignore"
    fi
    printf '.cicd/out/\n' >> "$gitignore"
fi

log "CICD installed at $target"
log "next: commit the new files, then push a PR to exercise the pipeline."
