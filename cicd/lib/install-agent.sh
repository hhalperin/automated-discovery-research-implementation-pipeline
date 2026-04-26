#!/usr/bin/env bash
# cicd/lib/install-agent.sh — install the Cursor CLI ("agent" binary).
#
# Usage:
#   cicd install-agent [--quiet] [--check] [--bin-dir <dir>]
#
# Strategy:
#   * If `agent` (or legacy `cursor-agent`) is already on PATH, no-op.
#   * Otherwise download via the official one-liner from cursor.com/install.
#   * The installer drops the binary in ~/.cursor/bin (current) or
#     ~/.local/bin (older); we prepend whichever exists to PATH for the
#     remainder of this shell, and (if running under GitHub Actions) also
#     append to $GITHUB_PATH so subsequent steps see it.
#
# Verification:
#   `agent --version` (or `cursor-agent --version`) must succeed.

set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

quiet=0
check_only=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet) quiet=1 ;;
        --check) check_only=1 ;;
        *) cicd::err "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

log() { (( quiet == 1 )) || cicd::log "$*"; }

cicd::install_agent::_resolve() {
    if command -v agent >/dev/null 2>&1; then
        command -v agent
        return 0
    fi
    if command -v cursor-agent >/dev/null 2>&1; then
        command -v cursor-agent
        return 0
    fi
    for cand in "$HOME/.cursor/bin/agent" "$HOME/.local/bin/agent"; do
        [[ -x "$cand" ]] && { printf '%s' "$cand"; return 0; }
    done
    return 1
}

if (( check_only == 1 )); then
    if path=$(cicd::install_agent::_resolve); then
        ver=$("$path" --version 2>/dev/null | head -1 || echo "unknown")
        log "Cursor CLI already installed: $path ($ver)"
        exit 0
    fi
    log "Cursor CLI not found"
    exit 1
fi

if path=$(cicd::install_agent::_resolve); then
    ver=$("$path" --version 2>/dev/null | head -1 || echo "unknown")
    log "Cursor CLI already installed: $path ($ver)"
    exit 0
fi

log "Installing Cursor CLI from https://cursor.com/install ..."
if ! command -v curl >/dev/null 2>&1; then
    cicd::err "curl is required to install the Cursor CLI"
    exit 1
fi
# The official installer is interactive in some cases; pipe it to bash.
# We tee the body so we can inspect on failure.
tmp_log=$(mktemp)
if ! curl -fsS https://cursor.com/install | bash 2>&1 | tee "$tmp_log"; then
    cicd::err "Cursor CLI installation failed; see $tmp_log"
    exit 1
fi
rm -f "$tmp_log"

# Find where it landed and put it on PATH for this session.
for cand_dir in "$HOME/.cursor/bin" "$HOME/.local/bin"; do
    if [[ -x "$cand_dir/agent" ]]; then
        case ":$PATH:" in
            *":$cand_dir:"*) ;;
            *) export PATH="$cand_dir:$PATH" ;;
        esac
        # Persist for subsequent GitHub Actions steps.
        if [[ -n "${GITHUB_PATH:-}" ]]; then
            echo "$cand_dir" >> "$GITHUB_PATH"
        fi
        log "Cursor CLI installed at $cand_dir/agent"
        "$cand_dir/agent" --version 2>/dev/null | head -1 || true
        exit 0
    fi
done

cicd::err "Cursor CLI installer ran but no 'agent' binary was found in ~/.cursor/bin or ~/.local/bin"
exit 1
