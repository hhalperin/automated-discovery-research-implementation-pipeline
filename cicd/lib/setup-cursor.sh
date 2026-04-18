#!/usr/bin/env bash
# cicd/lib/setup-cursor.sh — programmatically wire Cursor into a GitHub repo.
#
# Does, in order:
#   1. Ensures `gh` is available and authenticated.
#   2. Detects the target repo (--repo OWNER/NAME or autodetect from remote).
#   3. Checks whether the Cursor GitHub App is installed on that repo.
#      Cursor's GitHub App MUST be installed via the human OAuth flow at
#      https://github.com/apps/cursor — GitHub does not expose an API to
#      install third-party apps. We detect, but do not (cannot) install.
#   4. Sets the repo secret CURSOR_API_KEY (from env or --api-key) via
#      `gh secret set`. Required for the CICD workflow's judges and for
#      Cloud Agents launched from the workflow.
#   5. Optionally enables Bugbot on the repo (manual, link printed).
#
# Usage:
#   cicd setup-cursor [--repo OWNER/NAME] [--api-key <key>]
#                     [--secret-name CURSOR_API_KEY] [--quiet]
#
# Exit codes:
#   0 — secret set; Cursor app status reported.
#   2 — usage error.
#   3 — gh not installed / not authenticated.
#   4 — Cursor app not installed on the target repo (action item printed).

set -euo pipefail
. "$CICD_ROOT/lib/common.sh"

repo=""
api_key="${CURSOR_API_KEY:-}"
secret_name="CURSOR_API_KEY"
quiet=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) repo="$2"; shift ;;
        --repo=*) repo="${1#*=}" ;;
        --api-key) api_key="$2"; shift ;;
        --api-key=*) api_key="${1#*=}" ;;
        --secret-name) secret_name="$2"; shift ;;
        --secret-name=*) secret_name="${1#*=}" ;;
        --quiet) quiet=1 ;;
        *) cicd::err "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

log() { (( quiet == 1 )) || printf '[cicd setup-cursor] %s\n' "$*" >&2; }

if ! command -v gh >/dev/null 2>&1; then
    cicd::err "gh CLI not installed"
    exit 3
fi
if ! gh auth status >/dev/null 2>&1; then
    cicd::err "gh CLI is not authenticated; run 'gh auth login' first"
    exit 3
fi

if [[ -z "$repo" ]]; then
    origin=$(git remote get-url origin 2>/dev/null || echo "")
    # Strip protocol + optional user:pass@ + host[/:], leaving owner/name(.git).
    repo=$(printf '%s' "$origin" \
        | sed -E 's#^(git@|https?://)##' \
        | sed -E 's#^[^@/]+@##' \
        | sed -E 's#^[^:/]+[:/]+##' \
        | sed -E 's#\.git$##')
fi
if [[ -z "$repo" ]]; then
    cicd::err "could not determine target repo; pass --repo OWNER/NAME"
    exit 2
fi
log "target repo: $repo"

# 1. Cursor GitHub App install detection.
# Strategy: try several read paths; each returns "installed", "not_installed",
# or "unknown" (token lacks scope). The repo-scoped /installation endpoint is
# the strongest signal because it works for any token with repo access.
log "checking Cursor GitHub App install on $repo ..."
installed_state="unknown"

# (a) repos/{repo}/installation — returns the *single* installation on the
# repo. 200 + app_slug=='cursor' means installed; 404 means not installed.
# Some tokens (Actions GITHUB_TOKEN) get 401 here; we treat that as unknown.
status_file=$(mktemp)
body=$(gh api -H 'Accept: application/vnd.github+json' \
       "repos/$repo/installation" 2>"$status_file" || true)
if printf '%s' "$body" | jq -e '.app_slug == "cursor"' >/dev/null 2>&1; then
    installed_state="installed"
elif printf '%s' "$body" | jq -e '.message? | test("Not Found"; "i")' >/dev/null 2>&1; then
    installed_state="not_installed"
fi
rm -f "$status_file"

# (b) user/installations — works with a personal access token.
if [[ "$installed_state" == "unknown" ]]; then
    if installations=$(gh api -H 'Accept: application/vnd.github+json' \
            "user/installations" --paginate 2>/dev/null); then
        if printf '%s' "$installations" \
               | jq -e '.installations[]?.app_slug | select(. == "cursor")' >/dev/null 2>&1; then
            installed_state="installed"
        else
            installed_state="not_installed"
        fi
    fi
fi

case "$installed_state" in
    installed)
        log "Cursor GitHub App is installed on $repo."
        ;;
    not_installed)
        cat >&2 <<EOF
[cicd setup-cursor] Cursor GitHub App is NOT installed on $repo.
GitHub does not allow third-party Apps to be installed via API; this is
the one human click in the whole flow:

    https://github.com/apps/cursor/installations/new

Or via the Cursor dashboard:

    https://cursor.com/dashboard  (Integrations → Connect GitHub)

Then re-run: cicd setup-cursor --repo $repo
EOF
        ;;
    unknown|*)
        cat >&2 <<EOF
[cicd setup-cursor] Could not determine Cursor App install status with the
current token (insufficient scope to list app installations). To verify:

    gh api repos/$repo/installation --jq '.app_slug'   # should print "cursor"

If not installed, install once at:
    https://github.com/apps/cursor/installations/new
EOF
        ;;
esac

# 2. Set the repo secret.
if [[ -z "$api_key" ]]; then
    cicd::err "no API key: pass --api-key <key> or export CURSOR_API_KEY"
    exit 2
fi

log "setting repo secret $secret_name on $repo ..."
if printf '%s' "$api_key" | gh secret set "$secret_name" --repo "$repo" --body - >/dev/null; then
    log "secret $secret_name set on $repo"
else
    cicd::err "failed to set secret $secret_name"
    exit 1
fi

# 3. Hint about Bugbot.
cat >&2 <<EOF
[cicd setup-cursor] Done. Next steps:

  * On any PR in $repo, comment "cursor review" or "bugbot run" to trigger
    Cursor Bugbot. Inline rule learning: "@cursor remember <fact>".
  * Workflows in this repo will now have CURSOR_API_KEY available, so the
    CICD judges can use the Cursor CLI as their LLM backend.

EOF

case "$installed_state" in
    installed) exit 0 ;;
    not_installed) exit 4 ;;
    *) exit 0 ;;
esac
