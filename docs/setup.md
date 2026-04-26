# Local Development Setup

This guide covers everything needed to run TLDR Research Ops locally. The system is currently in the planning phase (P1 MVP); this document will be updated as the implementation evolves.

For how this repository is laid out (docs, automation, CICD, workflows), see [ARCHITECTURE.md](../ARCHITECTURE.md) at the repo root.

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Python | 3.11+ | Recommended: use `pyenv` or Windows Python launcher |
| Git | 2.40+ | See [git-credentials-windows-setup.md](git-credentials-windows-setup.md) for Windows credential setup |
| OpenAI API key | — | Required for all LLM-driven stages |
| GitHub PAT | — | Required for repo analysis and (optionally) PR creation |
| Gmail API credentials | — | Required for production ingestion (P5); not needed for MVP |

## Quickstart

```powershell
# 1. Clone the repo
git clone https://github.com/hhalperin/automated-discovery-research-implementation-pipeline.git
cd automated-discovery-research-implementation-pipeline

# 2. Create and activate virtual environment
python -m venv .venv
.venv\Scripts\Activate.ps1

# 3. Install dependencies
pip install -r requirements.txt

# 4. Copy env template and fill in your secrets
copy .env.example .env
# Edit .env — see "Secrets & environment variables" below

# 5. Validate setup
python -m tldr validate-env
```

> Note: `requirements.txt` and `tldr` package do not exist yet. This will be updated when P1 implementation begins.

## Secrets & environment variables

**Never commit secrets to the repo.** All tokens live in `.env` (local) or GitHub Actions Secrets (CI). `.env` is in `.gitignore`.

Copy `.env.example` to `.env` and populate:

```dotenv
# Required for all LLM stages
OPENAI_API_KEY=sk-...

# Required for repo analysis (read-only PAT minimum)
GITHUB_TOKEN=ghp_...

# Required only for production ingestion (P5)
# GMAIL_CLIENT_ID=...
# GMAIL_CLIENT_SECRET=...

# Run config overrides (optional; see config/run-config.yaml for defaults)
# TLDR_TOP_N=5
# TLDR_MAX_TOKENS=50000
# TLDR_MAX_WALL_SECONDS=300
```

See [docs/adr/ADR-0003-auth-secrets-least-privilege.md](adr/ADR-0003-auth-secrets-least-privilege.md) for the full token scope model and rotation strategy.

## Run configuration

Default run configuration lives in `config/run-config.yaml` (to be created during P1). Environment variables prefixed `TLDR_` override any config file value at runtime — useful for CI without modifying committed config.

Key configuration knobs (see [ADR-0009](adr/ADR-0009-cost-time-controls.md) and [ADR-0010](adr/ADR-0010-triage-scoring.md)):

| Key | Default | Description |
|-----|---------|-------------|
| `top_n` | `5` | Maximum opportunities to process per run |
| `depth_threshold_deep` | `0.75` | OpportunityScore >= this → deep plan |
| `depth_threshold_medium` | `0.50` | OpportunityScore >= this → medium plan |
| `max_tokens_per_run` | TBD | Hard token cap across all OpenAI calls in one run |
| `max_wall_seconds` | TBD | Hard wall-clock cap; run stops gracefully if exceeded |
| `fetch_cap_per_stage` | TBD | Max external URLs fetched per pipeline stage |

## Running the pipeline (MVP)

The MVP (P1) uses manual newsletter paste. Once implemented:

```powershell
# Run with a newsletter text file
python -m tldr run --input newsletter.txt

# Run with manual paste (interactive)
python -m tldr run --paste

# Dry run: extract candidates only, no evidence or plans
python -m tldr run --input newsletter.txt --dry-run
```

Artifacts are written to `storage/runs/<run-id>/` by default. See [ADR-0005](adr/ADR-0005-artifact-storage.md) for the storage layout.

## Development workflow

### Branching

- `main`: stable; all changes via PR
- Feature branches: `feature/<short-description>`
- ADR drafts: `adr/<adr-number>-<short-title>`

See [ADR-0006](adr/ADR-0006-safety-gates-codegen.md) for branch strategy related to automated PRs.

### Running tests

```powershell
# Unit tests
pytest tests/unit/

# Integration tests (requires .env populated)
pytest tests/integration/

# Replay/regression tests (requires stored run artifacts)
pytest tests/regression/
```

Test strategy (to be elaborated in a testing ADR or child plan):
- **Unit:** mock all external calls (OpenAI, GitHub, Gmail); test artifact schemas and scoring logic
- **Integration:** run against real APIs with a capped config (`TLDR_TOP_N=1`, `TLDR_MAX_TOKENS=5000`)
- **Regression:** replay stored newsletter inputs against frozen artifacts to catch regressions in schema or scoring

### Linting & formatting

```powershell
# Lint
ruff check src/

# Format
ruff format src/

# Type check
mypy src/
```

CI runs these on every PR. Do not merge with lint errors.

### Schema validation

Artifacts are schema-validated at stage boundaries. To validate an artifact manually:

```powershell
python -m tldr validate-artifact --file storage/runs/<run-id>/opportunity-score.json
```

See [ADR-0002](adr/ADR-0002-artifact-pipeline-schemas.md) for the schema strategy.

## Artifacts & storage

Each pipeline run produces a directory at `storage/runs/<run-id>/`:

```
storage/runs/<run-id>/
  run-manifest.json         # always present; tracks stage results, timings, config snapshot
  headline-candidates.json
  opportunity-scores.json
  evidence-pack-<slug>.json
  learning-plan-<slug>.json
  implementation-plan-<slug>.json
  codex-brief-<slug>.json   # optional; only when explicitly enabled
  digests/                  # human-readable summaries per artifact
```

See [ADR-0005](adr/ADR-0005-artifact-storage.md) for retention policy and archival decisions.

## Debugging failed runs

1. Check `storage/runs/<run-id>/run-manifest.json` — it records per-stage success/fail, timings, and stop conditions.
2. Check `logs/<run-id>.log` for structured stage logs.
3. If a stage failed mid-run, artifacts from prior stages are valid; you can re-run from the failed stage once the issue is fixed (idempotent re-runs are a design goal; see FR1 dedupe).
4. Rate limit errors: check RunManifest `actual_token_spend` vs `max_tokens_per_run`. Increase cap or reduce `top_n`.
5. OpenAI errors: check API key validity and quota.
6. GitHub errors: check PAT scopes against [ADR-0003](adr/ADR-0003-auth-secrets-least-privilege.md) token scope table.

## CI/CD

GitHub Actions workflows (to be created in P5):

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR, push to main | Lint, type check, unit tests, schema validation |
| `pipeline.yml` | Schedule (cron) + `workflow_dispatch` | Production pipeline run |
| `regression.yml` | PR (optional) | Replay stored runs; fail if artifacts diverge |

Secrets required in GitHub Actions:
- `OPENAI_API_KEY`
- `GITHUB_TOKEN` (automatic in Actions for read-only; provide PAT for write operations)
- `GMAIL_CREDENTIALS` (P5+)

## Environment parity

| Setting | Local | CI (GitHub Actions) |
|---------|-------|---------------------|
| Secrets | `.env` file | Repository Secrets |
| Config | `config/run-config.yaml` + `.env` overrides | Same config file + Actions env vars |
| Storage | `storage/runs/` (local filesystem) | TBD (see ADR-0005) |
| Scheduling | Manual invocation / Windows Task Scheduler | GitHub Actions cron |

Keep local and CI config in sync. If you change a cap in `run-config.yaml`, verify CI workflows still pass within the new limits.
