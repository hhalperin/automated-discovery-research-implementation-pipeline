---
planId: pipeline-implementation
title: "Pipeline: Implementation — RepoFitAssessment + ImplementationPlan Generation"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Pipeline: Implementation — RepoFitAssessment + ImplementationPlan Generation

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0007: [RepoRegistry Design](../../docs/adr/ADR-0007-repo-registry.md)
- ADR-0002: [Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
- ADR-0009: [Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)
- PRD FR6 (Repo allowlist + repo-fit), FR7 (ImplementationPlan generation)

## Purpose

For each `deep`-depth opportunity with a `LearningPlan` and `EvidencePack`, produce a `RepoFitAssessment` for each allowlisted repo and then generate an `ImplementationPlan` for the best-fit repo. Only repos registered in the `RepoRegistry` may be targeted. The dual-plan model is enforced: `LearningPlan` and `ImplementationPlan` are separate artifacts produced in separate stages.

## Scope

- `src/tldr_ops/stages/05_implementation.py` — stage runner
- `src/tldr_ops/implementation.py` — repo-fit scoring + plan generation
- `src/tldr_ops/prompts/implementation.py` — LLM prompts for fit assessment and plan generation
- Output: `RepoFitAssessment` list + `ImplementationPlan` per qualifying candidate, written to `run_dir/05-implementation/`
- Allowlist enforcement: only registry repos analyzed or targeted (non-negotiable invariant)

## Dependencies

- **Depends on:** `infra-bootstrap`, `pipeline-triage` (RepoRegistry loaded), `pipeline-learning` (LearningPlan available), `pipeline-evidence` (EvidencePack available)
- **Blocks:** `pipeline-codegen`

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:**
- RepoFitAssessment for each (candidate × repo) pair is independent; can parallelize.
- ImplementationPlan generation is sequential per candidate (depends on all fit assessments for that candidate).

**Phase gates:**
- Allowlist check must be implemented before any repo analysis begins.
- Do not mark this plan complete until a fixture LearningPlan + EvidencePack produces a valid `ImplementationPlan` with MVP and ideal options.

**Delegation triggers:**
- If prompt engineering for multi-option plans (MVP vs. ideal) produces incoherent options, delegate a prompt-design subagent.

**Verification:** `pytest tests/test_implementation.py` passes; fixture test produces `ImplementationPlan` with ≥ 2 options, each with non-empty `tasks`, `acceptance_criteria`, and `rollback_steps`.

## TODOs

### Group 1: Allowlist enforcement (non-negotiable invariant)

- [ ] Implement `get_eligible_repos(registry: RepoRegistry, action: Literal["analyze","write","prototype"]) -> list[RepoEntry]` in `src/tldr_ops/implementation.py`: filters registry to repos where `action` is in `allowed_actions`. Acceptance: registry with 3 repos (1 analyze-only, 2 allowing prototype) returns 2 repos for `action="prototype"`; 3 for `action="analyze"`.
- [ ] Add guard in stage runner: before any repo analysis, assert that the target repo is in the registry and has the required action permitted; raise `AllowlistViolationError` if not. Acceptance: targeting a repo not in the registry raises `AllowlistViolationError`; targeting a registered repo with correct action proceeds.

### Group 2: RepoFitAssessment

- [ ] Design repo-fit assessment prompt in `src/tldr_ops/prompts/implementation.py`: given a candidate opportunity (from LearningPlan summary + EvidencePack), a repo's `stack`, `goals`, `constraints`, and `integration_surfaces`, ask the LLM to produce a `fit_score` (0–1) and a `fit_reasoning` string plus a list of `recommended_integration_points`. Output: JSON. Acceptance: prompt defined as constant; requires explicit `fit_score` and reasoning.
- [ ] Implement `assess_repo_fit(candidate: HeadlineCandidate, learning_plan: LearningPlan, evidence: EvidencePack, repo: RepoEntry, config: RunConfig, openai_client) -> RepoFitAssessment`: calls fit prompt, parses JSON, validates against `RepoFitAssessment` model. Acceptance: mocked LLM response produces valid `RepoFitAssessment`.
- [ ] Run fit assessment for all eligible repos and select the best-fit repo: `select_best_fit(assessments: list[RepoFitAssessment]) -> RepoFitAssessment | None`. Returns `None` if all repos score < 0.3 (no fit). Acceptance: all-low-fit returns `None`; otherwise returns highest-scoring assessment.

### Group 3: ImplementationPlan generation

- [ ] Design implementation plan prompt: given candidate opportunity, LearningPlan key takeaways, EvidencePack unknowns, selected repo's constraints + integration surfaces, produce a plan with two options: MVP (minimal working change) and ideal (full implementation). Each option has `label`, `tasks` (list), `dependencies` (list), `acceptance_criteria` (list), `rollout_steps` (list), `rollback_steps` (list). Output: JSON. Acceptance: prompt defined; requires two options.
- [ ] Implement `generate_implementation_plan(candidate: HeadlineCandidate, learning_plan: LearningPlan, evidence: EvidencePack, fit: RepoFitAssessment, config: RunConfig, openai_client) -> ImplementationPlan`: calls plan prompt, parses, validates. Acceptance: mocked LLM produces valid `ImplementationPlan` with `options` list of length ≥ 2.
- [ ] Enforce dual-plan model: if `LearningPlan` for a candidate is missing, raise `DualPlanViolationError` rather than generating an `ImplementationPlan` without it. Acceptance: missing `LearningPlan` raises `DualPlanViolationError`; present plan proceeds.

### Group 4: Stage runner + artifact output

- [ ] Implement `run_implementation_stage(run_dir: Path, candidates: list[HeadlineCandidate], scores: list[OpportunityScore], evidence_packs: list[EvidencePack], learning_plans: list[LearningPlan], registry: RepoRegistry, config: RunConfig, openai_client) -> list[ImplementationPlan]` in `stages/05_implementation.py`: filters to `deep`-depth candidates with both EvidencePack and LearningPlan; runs fit assessments; skips if no repo fits; generates ImplementationPlan for best-fit repo; writes artifacts to `run_dir/05-implementation/`. Acceptance: only deep candidates with full evidence and learning context produce plans; missing preconditions are logged and skipped.
- [ ] Write `RepoFitAssessment` list artifact alongside `ImplementationPlan` for each candidate. Acceptance: `run_dir/05-implementation/{slug}-fit.json` exists and validates.

### Group 5: Tests

- [ ] Write `tests/test_implementation.py`: test `get_eligible_repos`, allowlist guard, `assess_repo_fit` (mocked LLM), `select_best_fit` (boundary cases), `generate_implementation_plan` (mocked), dual-plan violation. Acceptance: `pytest tests/test_implementation.py -v` passes.
- [ ] Add `tests/fixtures/implementation-plan-sample.json`: a fixture `ImplementationPlan` with 2 options. Acceptance: validates against `ImplementationPlan` schema.
