---
planId: pipeline-learning
title: "Pipeline: Learning — LearningPlan + LearningDigest Generation"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Pipeline: Learning — LearningPlan + LearningDigest Generation

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0010: [Triage Scoring Algorithm & Depth Policy](../../docs/adr/ADR-0010-triage-scoring.md)
- ADR-0002: [Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
- ADR-0009: [Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)
- PRD FR5 (LearningPlan generation)

## Purpose

For each candidate with an `EvidencePack`, produce a `LearningPlan` calibrated to the assigned depth (skim/medium/deep) and a concise `LearningDigest`. The LearningPlan implements the "learn enough to decide" framing: it includes explicit stop conditions and decision checkpoints so the user knows when to proceed vs. research more.

## Scope

- `src/tldr_ops/stages/04_learning.py` — stage runner
- `src/tldr_ops/learning.py` — plan + digest generation logic
- `src/tldr_ops/prompts/learning.py` — depth-calibrated LLM prompts
- Output: `LearningPlan` + `LearningDigest` per qualifying candidate, written to `run_dir/04-learning/`
- Evidence-gated: stage aborts for any candidate missing its `EvidencePack` (non-negotiable invariant)

## Dependencies

- **Depends on:** `infra-bootstrap`, `pipeline-evidence` (EvidencePack required per candidate)
- **Blocks:** `pipeline-implementation`

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:**
- Learning plan generation per candidate is independent; can parallelize with `asyncio.gather` for multiple candidates.
- If prompt engineering for depth calibration (skim vs. medium vs. deep sections) requires iteration, delegate a prompt-design subagent.

**Phase gates:**
- Evidence-gate check must be implemented before any LLM call; no plan is generated for a candidate without an EvidencePack.
- Do not mark this plan complete until a fixture `EvidencePack` produces a `LearningPlan` with non-empty `sections`, `stop_conditions`, and `decision_checkpoints`.

**Delegation triggers:**
- If depth-differentiated prompts are hard to calibrate, delegate a subagent to compare prompt variants across fixture EvidencePacks.

**Verification:** `pytest tests/test_learning.py` passes; end-to-end test with fixture EvidencePack produces a `LearningPlan` with correct depth-appropriate section count.

## TODOs

### Group 1: Evidence gate + depth routing

- [ ] Implement `check_evidence_gate(candidate_id: str, evidence_packs: list[EvidencePack]) -> EvidencePack` in `src/tldr_ops/learning.py`: finds the EvidencePack for the given candidate_id; raises `EvidenceGateError` if not found. Acceptance: missing EvidencePack raises `EvidenceGateError("No EvidencePack for candidate '{id}' — learning stage aborted")`; found pack is returned.
- [ ] Implement `get_depth_config(score: OpportunityScore, config: RunConfig) -> Literal["skim","medium","deep"]`: reads `score.recommended_depth` but applies `config.depth_override[candidate_id]` if present. Acceptance: override takes precedence over score-assigned depth; absent override returns `score.recommended_depth`.

### Group 2: LLM prompts (depth-calibrated)

- [ ] Design skim-depth LearningPlan prompt in `src/tldr_ops/prompts/learning.py`: 1–2 section plan; no evidence fetching required; output must include at least 1 stop condition ("stop if this confirms/denies X") and 1 decision checkpoint. Output: JSON with `sections`, `stop_conditions`, `decision_checkpoints`. Acceptance: prompt defined as constant; requires JSON output.
- [ ] Design medium-depth prompt: 3–5 section plan; references specific claims from the EvidencePack; includes uncertainty flag for low-confidence claims; 2–3 stop conditions. Acceptance: prompt references `{{evidence_summary}}` template variable that is populated with a summary of the EvidencePack.
- [ ] Design deep-depth prompt: 5–8 section plan; addresses all unknowns from EvidencePack explicitly; includes a "contradictions to investigate" section if contradictions exist; 3–5 stop conditions and checkpoints. Acceptance: prompt references both `{{unknowns}}` and `{{contradictions}}` template variables.
- [ ] Design LearningDigest prompt: given a `LearningPlan`, produce a 3–5 sentence summary + 3–5 key takeaways as JSON. Acceptance: prompt defined; output schema matches `LearningDigest.key_takeaways` (list[str]).

### Group 3: Generation logic

- [ ] Implement `generate_learning_plan(candidate: HeadlineCandidate, evidence: EvidencePack, depth: str, config: RunConfig, openai_client) -> LearningPlan` in `learning.py`: selects the appropriate depth prompt, populates template variables from the EvidencePack, calls LLM, parses JSON, validates against `LearningPlan` model. Acceptance: mocked LLM returning valid JSON produces a `LearningPlan` with non-empty `sections`, `stop_conditions`, `decision_checkpoints`.
- [ ] Implement `generate_digest(plan: LearningPlan, config: RunConfig, openai_client) -> LearningDigest`: calls digest prompt with the plan's sections, parses response. Acceptance: mocked response produces `LearningDigest` with `summary` (str) and `key_takeaways` (list ≥ 3 items).
- [ ] Enforce `low_confidence` propagation: if `OpportunityScore.low_confidence` is `True`, include a prominent uncertainty note in the plan's first section. Acceptance: plan for a low-confidence score has a section beginning with "Note: confidence is low…".

### Group 4: Stage runner + artifact output

- [ ] Implement `run_learning_stage(run_dir: Path, candidates: list[HeadlineCandidate], scores: list[OpportunityScore], evidence_packs: list[EvidencePack], config: RunConfig, openai_client) -> list[LearningPlan]` in `stages/04_learning.py`: for each candidate with `recommended_depth != "skim"` and an EvidencePack, generates plan + digest, writes both to `run_dir/04-learning/{slug}-learning.json` and `{slug}-digest.json` + companion `.md` files. Returns list of `LearningPlan` objects. Acceptance: skim candidates are skipped; each non-skim candidate with an EvidencePack produces two artifacts.
- [ ] Implement wall-clock budget check: abort remaining candidates if budget is near exhausted; set `stop_condition_triggered` in stage output. Acceptance: very short `max_wall_seconds` triggers early stop.

### Group 5: Tests

- [ ] Write `tests/test_learning.py`: test `check_evidence_gate` (found and missing cases), `get_depth_config` (override and no-override), `generate_learning_plan` (mocked LLM, all 3 depths), `generate_digest` (mocked). Acceptance: `pytest tests/test_learning.py -v` passes.
- [ ] Add `tests/fixtures/learning-plan-medium-sample.json`: a fixture `LearningPlan` (depth=medium) for downstream tests. Acceptance: validates against `LearningPlan` schema.
