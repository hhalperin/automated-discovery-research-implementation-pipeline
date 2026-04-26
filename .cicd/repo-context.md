# Repo context for CICD judges (this repo)

## What this repo is

- **Purpose:** hosts CICD — a universal, drop-in Continuous-Agent /
  Continuous-Development pipeline for GitHub Actions — along with the
  original TLDR Research Ops planning artifacts.
- **Primary language:** Bash + Python (stdlib + PyYAML + optional openai).
- **Public surface:** the `cicd/` directory (CLI, library, prompts,
  templates, tests) and associated GitHub Actions workflows. Everything
  else is planning / documentation.

## Conventions this repo expects

- **Branching:** `^(cursor|feature|fix|chore|docs|adr)\/[a-z0-9][a-z0-9._-]*$`.
- **Tests:** bash-driven; the full suite lives at `cicd/tests/run-tests.sh`.
- **Docs:** live under `docs/cicd/`. Code changes in `cicd/` should
  update `docs/cicd/` when they change user-visible behaviour.

## Hazards / footguns

- `cicd/install.sh` must refuse to self-copy when installed into the
  CICD source repo (the target's `cicd/` would otherwise be deleted).
- Check scripts must never import network calls. Only judges do.
- Judges must default to `verdict: skipped` whenever an LLM backend is
  unavailable — they must never block the pipeline implicitly.

## Non-goals

- No deployment. CICD stops at the branch.
