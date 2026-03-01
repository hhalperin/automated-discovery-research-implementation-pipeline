---
planId: pipeline-codegen
title: "Pipeline: Codegen Safety Gates + CodexExecutionBrief"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Pipeline: Codegen Safety Gates + CodexExecutionBrief

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0006: [Safety Gates for Codegen / PR Creation](../../docs/adr/ADR-0006-safety-gates-codegen.md)
- ADR-0003: [Auth, Secrets, and Least-Privilege Access Model](../../docs/adr/ADR-0003-auth-secrets-least-privilege.md)
- ADR-0007: [RepoRegistry Design](../../docs/adr/ADR-0007-repo-registry.md)
- ADR-0009: [Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)
- PRD FR8 (Codex execution, gated), N1 (Non-goal: no autonomous shipping)

## Purpose

Implement the optional, gated final stage: generating a `CodexExecutionBrief` from an `ImplementationPlan` and walking it through the two-gate safety check before any branch or PR is created. Default is read-only; this stage does nothing unless `codegen_enabled: true` is explicitly set and the user approves interactively.

## Scope

- `src/tldr_ops/codegen_gate.py` — two-gate check logic (config flag + interactive approval)
- `src/tldr_ops/stages/06_codegen.py` — stage runner
- `src/tldr_ops/codegen.py` — CodexExecutionBrief generation + GitHub branch/PR operations
- `src/tldr_ops/prompts/codegen.py` — LLM prompt for brief generation
- Output: `CodexExecutionBrief` artifact (if approved); `codegen_gate_result` recorded in RunManifest

## Dependencies

- **Depends on:** `infra-bootstrap` (auth, config, storage, schemas), `pipeline-implementation` (ImplementationPlan per candidate)
- **Blocks:** nothing (terminal stage)

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:**
- Gate logic and brief generation are strictly sequential (gate must pass before generation begins).
- GitHub branch operations can be implemented in a separate subagent session.

**Phase gates:**
- Gate check must be implemented and tested before any GitHub write operations are added.
- Do not implement GitHub PR creation until brief generation is validated with mock gate approval.
- Do not mark this plan complete until `codegen_enabled=False` (default) causes the stage to produce `codegen_gate_result: "skipped"` with no side effects.

**Delegation triggers:**
- If GitHub API (PyGithub or gh CLI) integration is ambiguous, delegate a research subagent.

**Verification:** `pytest tests/test_codegen.py` passes; with `codegen_enabled=False`, stage produces `skipped` result and zero GitHub calls; with `codegen_enabled=True` + mocked approval, brief is generated and `approved` result recorded.

## TODOs

### Group 1: Two-gate check (ADR-0006)

- [ ] Implement `check_codegen_gate(config: RunConfig) -> bool` in `src/tldr_ops/codegen_gate.py`: Gate 1 — returns `False` immediately if `config.codegen_enabled` is `False`. Gate 2 — validates that `TLDR_CODEGEN_AUTO_APPROVE` env var is set, OR presents an interactive `input()` prompt summarizing the brief and requiring the user to type `yes`. Returns `True` only if both gates pass. Acceptance: `codegen_enabled=False` returns `False` without any prompt; `codegen_enabled=True` with `TLDR_CODEGEN_AUTO_APPROVE=true` env var returns `True` without interactive prompt.
- [ ] Implement `validate_registry_allows_codegen(repo: RepoEntry) -> None`: raises `AllowlistViolationError` if `"prototype"` and `"write"` are both absent from `repo.allowed_actions`. Acceptance: analyze-only repo raises `AllowlistViolationError`; prototype repo passes.
- [ ] Implement `require_write_token_loaded(config: RunConfig)`: calls `auth.require_write_token(config)` to confirm write-scoped token is available. Raised `PermissionError` is re-raised with additional context. Acceptance: missing `GITHUB_WRITE_PAT` with `codegen_enabled=True` raises `PermissionError`.

### Group 2: CodexExecutionBrief generation

- [ ] Design brief generation prompt in `src/tldr_ops/prompts/codegen.py`: given an `ImplementationPlan` (MVP option), the target repo's `stack` and `constraints`, produce a `CodexExecutionBrief` with `branch_name`, `diff_summary`, `tests_to_run` (list), `acceptance_criteria` (list), `rollback_steps` (list). Output: JSON. Branch name must follow `codex/auto/{slug}-{YYYYMMDD}`. Acceptance: prompt defined; requires explicit `tests_to_run` and `rollback_steps`.
- [ ] Implement `generate_brief(plan: ImplementationPlan, repo: RepoEntry, config: RunConfig, openai_client) -> CodexExecutionBrief`: calls brief prompt, parses, validates against `CodexExecutionBrief` model. Sets `approved_by: None` (populated after gate approval). Acceptance: mocked LLM response produces valid brief.
- [ ] Implement approval recording: after gate passes, set `brief.approved_by = "human"` (interactive) or `brief.approved_by = "auto-env"` (TLDR_CODEGEN_AUTO_APPROVE). Acceptance: brief written to disk contains the correct `approved_by` value.

### Group 3: GitHub operations

- [ ] Implement `create_branch(repo: RepoEntry, branch_name: str, config: RunConfig)` in `codegen.py`: uses `GITHUB_WRITE_PAT` (loaded via `auth.get_secret`) and the GitHub API (via `PyGithub` or `gh` CLI subprocess) to create the branch from `main`. Raises `GitHubError` on failure. Acceptance: with a mocked GitHub API, branch creation is called with the correct parameters.
- [ ] Implement `open_draft_pr(repo: RepoEntry, branch_name: str, brief: CodexExecutionBrief) -> str` (returns PR URL): opens a draft PR with the brief's `diff_summary` as body and `acceptance_criteria` as a checklist. Acceptance: mocked GitHub API call receives expected PR body; returns URL string.
- [ ] Implement rollback helpers documented in the brief: `close_pr(pr_url: str)` and `delete_branch(repo: RepoEntry, branch_name: str)`. Acceptance: mocked calls invoke the correct GitHub API endpoints.

### Group 4: Stage runner + artifact output

- [ ] Implement `run_codegen_stage(run_dir: Path, plans: list[ImplementationPlan], registry: RepoRegistry, config: RunConfig, openai_client) -> dict` in `stages/06_codegen.py`: for each plan, checks gate, generates brief if approved, writes brief to `run_dir/06-codegen/{slug}-brief.json` + `.md`. Returns `{"gate_result": "skipped"|"approved"|"rejected", "briefs": [...]}`. Records result in RunManifest. Acceptance: with `codegen_enabled=False`, produces `gate_result="skipped"`, no brief files, no GitHub API calls.
- [ ] Ensure write-scoped token is never loaded when `codegen_enabled=False`. Acceptance: with `codegen_enabled=False`, `auth.get_secret(SECRET_GITHUB_WRITE_PAT)` is never called (verified by mock assertion).

### Group 5: Tests

- [ ] Write `tests/test_codegen.py`: test `check_codegen_gate` (disabled, auto-approve, interactive mock), `validate_registry_allows_codegen` (allowed/blocked), `generate_brief` (mocked LLM), `create_branch` (mocked GitHub), full stage with `codegen_enabled=False` (skipped, zero GitHub calls). Acceptance: `pytest tests/test_codegen.py -v` passes.
