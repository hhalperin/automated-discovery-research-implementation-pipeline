# ADR-0001: Execution & Scheduling Strategy

Status: Accepted
Date: 2026-02-24

## Context

The pipeline must run on a schedule to process morning newsletters. MVP needs a local option (Windows); production needs a reliable, auditable scheduler that integrates with secrets management and supports manual triggering. Two primary candidates are a local Windows Task Scheduler wrapper and GitHub Actions (cron + workflow_dispatch).

## Decision

**Dual-mode: A1 for MVP, A2 for production.**

- **MVP**: Pipeline invoked manually via `python -m tldr_ops run` or `tldr-ops run` CLI entry point. Windows Task Scheduler may optionally wrap this for daily automation but is not required to start.
- **Production**: GitHub Actions workflow with `schedule: [{cron: "0 7 * * 1-5"}]` + `workflow_dispatch` for on-demand re-runs. The workflow calls the same Python entry point, so no separate production code path exists.
- A single `run.py` entry point handles both modes; the scheduler is just the trigger.

## Alternatives considered

- **A1 (MVP, adopted)**: Simple, no external deps. Sufficient for getting first runs in quickly.
- **A2 (production, adopted)**: GitHub Actions provides secrets management, run logs, manual re-runs, and email notifications on failure — all required for operability (NFR4).
- **A3: ChatGPT scheduled tasks** — deferred. Cannot execute Python; useful only as a future notification layer. Does not replace execution scheduling.

## Consequences

- Entry point: `src/tldr_ops/__main__.py` (invoked via `python -m tldr_ops`) with a `run` subcommand.
- GitHub Actions workflow file: `.github/workflows/daily-run.yml`.
- Secrets handling follows two paths: keyring for local, GitHub Actions secrets for CI (see ADR-0003).
- Retry policy: max 2 retries per stage, exponential backoff; retries count against the fetch cap (ADR-0009).
- Stop condition: RunManifest records `exit_reason` (completed | stop_condition_triggered | error).

## Notes / Follow-ups

- Implements NFR4 (Operability) and FR9 (Storage + audit).
- Secrets handling strategy depends on chosen scheduler (see ADR-0003).
- Must define retry policy, cost caps, and "stop conditions" for runs.
