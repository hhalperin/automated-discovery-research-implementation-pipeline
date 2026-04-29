# tldr — Research Ops Pipeline

Multi-stage pipeline: ingestion → triage → evidence → learning → codegen.
Currently in **infra bootstrap phase** — see `docs/adr/` for design and `docs/prd/` for product framing.

## Tech stack (target)
- Python via `uv`; tests with `pytest`; lint with `ruff`; types with `mypy`.
- PowerShell admin scripts in `scripts/`.

## Conventions
- Architecture changes go through ADRs in `docs/adr/`. Add a new ADR before changing module boundaries.
- Research output (including external research like `docs/research/claude/`) is **read-only context** — don't restructure it without an ADR.
- No secrets in repo. `.env` is gitignored and read-blocked.

## Branching
- Feature branches: `feature/<topic>`, `fix/<topic>`, `docs/<topic>`. PRs into `main`.
- See `docs/research/claude/guardrails.md` for the full security profile.
