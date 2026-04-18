# AGENTS.md — context for autonomous agents working in this repo

## Cursor secrets and env vars

This repo runs under the user's Cursor account. Two distinct stores
provide credentials, and they are commonly conflated:

| Store | UI location | Purpose |
|-------|-------------|---------|
| **User API Keys** | `cursor.com/dashboard → Settings → API Keys` | The raw `crsr_…` / `key_…` strings issued by Cursor. Authenticate to Cursor's API (Cloud Agents API, headless CLI). Copy values out and paste where needed (`gh secret set …`). |
| **My Secrets** | `cursor.com/dashboard → Cloud Agents → Secrets` | Key/value store. Each secret has a **scope** (`All Repositories` or a specific `owner/repo`). When a Cloud Agent VM launches against a matching repo, Cursor injects the secret as an env var whose name = the secret name. |

### How to know what's available in the current VM

```bash
echo "$CLOUD_AGENT_INJECTED_SECRET_NAMES"   # comma-separated names
echo "$CURSOR_AGENT"                        # "1" inside a Cursor VM (marker only, not a credential)
```

Anything not in `$CLOUD_AGENT_INJECTED_SECRET_NAMES` is **not** present
in this VM, regardless of what exists in the Cursor dashboard. That
typically means the secret's repo scope does not include this repo.

### Current scope as of this writing

| Secret | Scope | Available here? |
|--------|-------|----------------|
| `ANTHROPIC_API_KEY` | All Repositories | ✅ |
| `GPAT` (GitHub PAT) | All Repositories | ✅ |
| `CURSOR_API_KEY` | `rolefinder/…` only | ❌ |
| `GITHUB_P…` | `rolefinder/…` only | ❌ |
| `ROLLER_A…` | `rolefinder/…` only | ❌ |

To make `CURSOR_API_KEY` available here:

1. **Cloud Agent path:** in the Cursor dashboard, edit the
   `CURSOR_API_KEY` secret and add this repo to its scope (or set to
   `All Repositories`). Next Cloud Agent run will have it.
2. **GitHub Actions path:** also add it as a repo secret so the CICD
   workflow can use it:
   ```bash
   ./cicd/bin/cicd setup-cursor --repo <owner>/<repo> --api-key "$CURSOR_API_KEY"
   ```

## CICD pipeline

This repo dogfoods CICD (`cicd/`). The PR workflow at
`.github/workflows/cicd.yml` runs deterministic gates + LLM judges on
every PR. See `docs/cicd/`.

LLM judge backend priority (auto-resolved):

1. `cursor-agent` — Cursor CLI on PATH + `CURSOR_API_KEY` set
2. `anthropic` — `ANTHROPIC_API_KEY` + `anthropic` Python SDK
3. `openai` — `OPENAI_API_KEY` + `openai` Python SDK
4. `stub` — judge emits `verdict: skipped`, never blocks

Override with `CICD_JUDGE_BACKEND=cursor-agent|anthropic|openai|stub`.

## GitHub credentials

Use `$GPAT` (or `$GITHUB_TOKEN` provided by the Cloud Agent harness)
when scripts need a token. `gh` is already authenticated on this VM.

## Testing convention

The CICD test suite lives at `cicd/tests/run-tests.sh` (bash, ~23
end-to-end assertions, runs in ~30s). Run it after any change to
`cicd/`. Static checks: `shellcheck -x -S warning cicd/bin/cicd
cicd/install.sh $(find cicd -name '*.sh')` and `actionlint
.github/workflows/cicd*.yml cicd/templates/workflows/*.yml`.
