# ADR-0003: Auth, Secrets, and Least-Privilege Access Model

Status: Accepted
Date: 2026-02-24

## Context

The pipeline uses OpenAI/Codex (API key), GitHub (read analysis and optional PR creation), and email ingestion (Gmail API or equivalent). Secrets must never appear in the repo, artifacts, or logs. Tokens must be rotation-ready and scoped to the minimum required permissions. The chosen secrets store depends on the scheduling strategy (ADR-0001).

## Decision

**A2 for local MVP (keyring), A1 for production (GitHub Actions secrets). Fine-grained PAT from A4.**

- **Local**: All secrets stored in OS keychain via the `keyring` Python library (`keyring.get_password("tldr-ops", key_name)`). No `.env` files.
- **Production (GitHub Actions)**: Secrets stored as repository-level Actions secrets; injected as env vars at workflow runtime.
- **GitHub auth**: fine-grained PAT (not classic PAT or GitHub App). Scoped per use:

| Token | Scopes | Used when |
|-------|--------|-----------|
| `GITHUB_READ_PAT` | `contents:read`, `metadata:read` | Always (analysis, RepoFitAssessment) |
| `GITHUB_WRITE_PAT` | `contents:write`, `pull-requests:write` | Only when `codegen_enabled: true` (ADR-0006) |
| `OPENAI_API_KEY` | n/a | Every run |
| `GMAIL_OAUTH_CREDENTIALS` | `gmail.readonly` | When Gmail ingestion enabled (ADR-0004) |

- Write-scoped PAT is never loaded unless `codegen_enabled: true` is explicitly set.
- Secret redaction: a middleware layer strips known secret values from all log lines and artifact fields before writing to disk.

## Alternatives considered

- **A1 (GitHub Actions, adopted for production)**: Best fit for CI; rotation via UI/API; env isolation per repo.
- **A2 (keyring, adopted for local)**: Zero file system risk; no external service dependency; works on Windows.
- **A3 (`.env` file)**: Rejected. Violates the "no secrets in repo" invariant; `.gitignore` is not a reliable safety gate.
- **A4 (fine-grained PAT, adopted over classic PAT/GitHub App)**: Fine-grained PATs allow exact permission scoping; GitHub App installation overhead unjustified for single-user tool.

## Consequences

- `src/tldr_ops/auth.py` module provides `get_secret(key: str) -> str` — reads from keyring locally, env var in CI.
- Rotation procedure: update keyring entry locally (`keyring.set_password`); update Actions secret via `gh secret set`.
- Secret redaction middleware applied to all `logging` calls and all artifact serialization paths.
- No secret appears in `RunManifest`, artifact `.json` files, or `.md` digests.

## Notes / Follow-ups

- Implements NFR3 (Safety) and G6 (Programmatic auth).
- Must define separate token scopes for read-only analysis vs PR creation (see ADR-0006).
- "No secrets in artifacts/logs" enforcement strategy must be explicit (e.g., redaction middleware, log scrubbing).
