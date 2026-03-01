# ADR-0006: Safety Gates for Codegen / PR Creation

Status: Accepted
Date: 2026-02-24

## Context

Codex execution (FR8) and PR creation must be explicitly gated behind human approval. The default pipeline mode is plan-only; no code is written unless the user opts in. Safety gates must prevent: unintended writes, scope creep in generated branches, and runaway cost from iterative Codex calls. The gate design must be simple enough to not impede legitimate use while being hard to accidentally bypass.

## Decision

**A1 + A4 combined: config flag as primary gate, interactive CLI prompt as secondary gate.**

**Gate sequence for any codegen/PR action:**
1. `RunConfig.codegen_enabled` must be `true` (default `false`). If false, `CodexExecutionBrief` generation is skipped entirely; no write-scoped token is loaded.
2. Target repo must have `prototype` or `write` in `allowed_actions` in `repo-registry.yaml` (ADR-0007).
3. Before submitting each brief: interactive CLI prompt displays the diff summary, branch name, and acceptance check list; user must type `yes` to proceed. Automation (GitHub Actions) must set `TLDR_CODEGEN_AUTO_APPROVE=true` explicitly to skip the prompt.

**Branch strategy:**
- Branch naming: `codex/auto/{opportunity-slug}-{YYYYMMDD}` (e.g., `codex/auto/adrvectordb-20260226`)
- Branches created from `main` (or configured base branch in `repo-registry.yaml`)
- One branch per `CodexExecutionBrief`

**Acceptance checks (required in CodexExecutionBrief):**
- `tests_to_run`: list of pytest paths or commands
- `acceptance_criteria`: list of human-readable checks
- `diff_summary`: short summary of changes (auto-generated)

**Rollback:**
1. `git branch -D {branch}` (local) or `gh api DELETE /repos/{owner}/{repo}/git/refs/heads/{branch}` (remote)
2. If PR was opened: `gh pr close {pr-number}`
3. Steps documented in CodexExecutionBrief so operator can follow them without context.

## Alternatives considered

- **A1 (config flag, adopted as primary gate)**: Hard to accidentally trigger; snapshotted in RunManifest for auditability.
- **A2 (separate execution mode command)**: Deferred. A separate command is useful UX but doesn't add safety beyond A1; could be added as a CLI alias later.
- **A3 (GitHub PR review gate)**: Deferred. Complements A1+A4 in production (Actions workflow can require review before merge); not needed for MVP.
- **A4 (interactive CLI approval, adopted as secondary gate)**: Catches cases where config was accidentally set to `true`; low infra overhead.

## Consequences

- `RunConfig.codegen_enabled: bool = False` (ADR-0009).
- `src/tldr_ops/codegen_gate.py` implements the two-gate check and interactive prompt.
- Write-scoped token (`GITHUB_WRITE_PAT`) is never loaded unless both gates pass.
- `RunManifest.codegen_gate_result` records: `skipped` | `approved` | `rejected` per brief.

## Notes / Follow-ups

- Implements FR8 (Codex execution gated) and NFR3 (Safety).
- CodexExecutionBrief must include: branch strategy, tests, acceptance checks, rollback steps.
- Must be consistent with least-privilege token model (ADR-0003): separate write-scoped token required.
- Default is N1 (Non-goal): no autonomous shipping without approval.
- Depends on ADR-0007 (RepoRegistry Design): the safety gate must validate that any branch or PR target is an allowlisted repo from the RepoRegistry before proceeding; the registry's `allowed_actions` field determines whether `write` or `prototype` actions are permitted.
