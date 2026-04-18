# Cursor integration for CICD

CICD ships with two Cursor integration points:

1. **LLM judges** (`improvement`, `quality`, `docs-accuracy`) can use the
   Cursor CLI as their backend instead of OpenAI.
2. **Cursor on PRs** — Bugbot reviews and `@cursor`-mention Cloud Agents,
   which work via Cursor's first-party GitHub App.

This guide walks through both, and what is and isn't programmable.

## TL;DR

```bash
# 1. Install the Cursor CLI locally (or in any CI runner).
./cicd/bin/cicd install-agent              # idempotent

# 2. Provision a repo: set CURSOR_API_KEY + check GitHub-App install.
./cicd/bin/cicd setup-cursor \
    --repo OWNER/REPO \
    --api-key "$CURSOR_API_KEY"

# 3. (One-time, human click — GitHub does not allow programmatic install.)
#    https://github.com/apps/cursor/installations/new
```

After that:

- The CICD workflow on each PR auto-installs the Cursor CLI on the runner
  whenever `CURSOR_API_KEY` is present, and the judges will pick it up
  automatically.
- On any PR, comment `cursor review` or `bugbot run` to invoke Bugbot.
- `@Cursor remember <fact>` teaches Bugbot a per-PR rule.

## 1. The Cursor CLI

Cursor renamed the binary from `cursor-agent` to **`agent`**. The
official installer drops it into `~/.cursor/bin` (current) or
`~/.local/bin` (older paths):

```bash
curl -fsS https://cursor.com/install | bash
agent --version
```

CICD's `install-agent` subcommand wraps that and:

- No-ops if `agent` (or legacy `cursor-agent`) is already on PATH.
- Adds the install dir to `$PATH` for the current shell.
- Appends to `$GITHUB_PATH` when running under GitHub Actions, so
  subsequent steps see the binary too.

```bash
./cicd/bin/cicd install-agent          # install if missing
./cicd/bin/cicd install-agent --check  # exit 0 if installed, 1 otherwise
```

CICD's judge runner (`cicd/lib/judges/_runner.sh`) prefers the Cursor
CLI when `CURSOR_API_KEY` is set, otherwise falls back to OpenAI, then
to a `skipped` stub. This is the default backend priority:

1. `agent` / `cursor-agent` on PATH and `CURSOR_API_KEY` set
2. `OPENAI_API_KEY` set + `openai` Python SDK importable
3. stub (judge emits `verdict: skipped`)

### Choosing a model

Set `CICD_CURSOR_MODEL` (e.g. `composer-2`, `gpt-5.2`, `opus-4.6`) to
pin a specific model for judges:

```yaml
env:
  CICD_CURSOR_MODEL: composer-2
```

## 2. Cursor on PRs (GitHub App)

**Bugbot** is Cursor's PR review bot. **It cannot be installed via API
— GitHub deliberately blocks programmatic installation of third-party
GitHub Apps.** This is the one human click in the whole workflow.

### Install (one-time, human action)

Either:

- Visit <https://github.com/apps/cursor/installations/new> and grant
  access to your repo or org, **or**
- Cursor dashboard → Integrations → Connect GitHub.

The app needs these permissions (granted by the OAuth flow):

| Permission | Why |
|------------|-----|
| Repository: Read & Write | Clone code, create branches |
| Pull requests: Read & Write | Open PRs, leave reviews/comments |
| Issues: Read & Write | Track bugs found in review |
| Checks & statuses: Read & Write | Report pass/fail on PRs |
| Actions & workflows: Read | Watch CI status |

CICD's `setup-cursor` subcommand probes whether the app is installed
and prints the install URL if not. It then sets the repo secret
`CURSOR_API_KEY` so the workflow's judges and Cloud Agents work:

```bash
export CURSOR_API_KEY=...   # from cursor.com → Settings → Integrations → API Keys
./cicd/bin/cicd setup-cursor --repo OWNER/REPO

# exit codes:
#   0 = secret set, app installed
#   2 = usage error
#   3 = gh CLI not installed / not authenticated
#   4 = secret set, but Cursor app not installed (action item printed)
```

### Triggering Bugbot

Cursor's bot user is **`@cursor`** on GitHub. Triggers on a PR:

| Comment | Effect |
|---------|--------|
| `cursor review` | Run Bugbot on the current PR (manual trigger). |
| `bugbot run` | Same as above. |
| `cursor review verbose=true` | Verbose run with request ID. |
| `@cursor remember <fact>` | Teach Bugbot a rule for this PR. |

Bugbot also runs automatically on every PR update if enabled per-repo
in the Cursor dashboard.

### Cloud Agents from PRs

Once the Cursor App is installed, you can spawn Cloud Agents from the
Cursor dashboard, the Cursor CLI (`agent -c "<prompt>"`), or the
existing TLDR-reader workflow in this repo
(`.github/workflows/tldr-reader-daily.yml`) — all three resolve to the
same `CURSOR_API_KEY`.

## 3. Why some things are not programmable

GitHub's REST API (`/v3/apps/installations`) lets you **list, query,
add a repository to, or remove a repository from** an existing GitHub
App installation, but **does not** let you create the installation
itself for an App you do not own. That is by design — only an
authenticated GitHub user (or org admin) can grant a third-party App
access. So the one-time install of the Cursor App must be done in a
browser. Everything else (CLI install, secret provisioning,
detection) is automated by CICD.

## 4. Workflow integration

The caller workflow (`.github/workflows/cicd.yml`) does:

```yaml
- name: Install Cursor CLI (for LLM judges)
  env:
    CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
  run: |
    [[ -z "${CURSOR_API_KEY:-}" ]] && exit 0
    ./cicd/bin/cicd install-agent

- name: Run CICD
  env:
    CURSOR_API_KEY:  ${{ secrets.CURSOR_API_KEY }}
    OPENAI_API_KEY:  ${{ secrets.OPENAI_API_KEY }}
    ...
```

When `CURSOR_API_KEY` is unset, the install step is a no-op and the
judges fall back to OpenAI / stub. The pipeline is never blocked by a
missing Cursor key.
