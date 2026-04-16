# Repo context for CACD judges (this repo)

## What this repo is

- **Purpose:** hosts CACD — a universal, drop-in Continuous-Agent /
  Continuous-Development pipeline for GitHub Actions — along with the
  original TLDR Research Ops planning artifacts.
- **Primary language:** Bash + Python (stdlib + PyYAML + optional openai).
- **Public surface:** the `cacd/` directory (CLI, library, prompts,
  templates, tests) and associated GitHub Actions workflows. Everything
  else is planning / documentation.

## Conventions this repo expects

- **Branching:** `^(cursor|feature|fix|chore|docs|adr)\/[a-z0-9][a-z0-9._-]*$`.
- **Tests:** bash-driven; the full suite lives at `cacd/tests/run-tests.sh`.
- **Docs:** live under `docs/cacd/`. Code changes in `cacd/` should
  update `docs/cacd/` when they change user-visible behaviour.

## Hazards / footguns

- `cacd/install.sh` must refuse to self-copy when installed into the
  CACD source repo (the target's `cacd/` would otherwise be deleted).
- Check scripts must never import network calls. Only judges do.
- Judges must default to `verdict: skipped` whenever an LLM backend is
  unavailable — they must never block the pipeline implicitly.

## Non-goals

- No deployment. CACD stops at the branch.
