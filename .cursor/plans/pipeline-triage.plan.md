---
planId: pipeline-triage
title: "Pipeline: Triage — Opportunity Scoring + RepoRegistry Loading"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Pipeline: Triage — Opportunity Scoring + RepoRegistry Loading

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0010: [Triage Scoring Algorithm & Depth Policy](../../docs/adr/ADR-0010-triage-scoring.md)
- ADR-0007: [RepoRegistry Design](../../docs/adr/ADR-0007-repo-registry.md)
- ADR-0002: [Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
- PRD FR3 (Triage scoring), FR6 (Repo allowlist — registry loading)

## Purpose

Implement the triage stage: for each `HeadlineCandidate`, produce an `OpportunityScore` using the weighted additive formula (ADR-0010), rank candidates, assign depth, and apply `top_n` cap. Also loads and validates the `RepoRegistry` so downstream stages have repo context available.

## Scope

- `src/tldr_ops/stages/02_triage.py` — stage runner
- `src/tldr_ops/triage.py` — scoring logic (formula, dimension extraction, depth assignment)
- `src/tldr_ops/registry.py` — RepoRegistry loader (ADR-0007)
- `src/tldr_ops/prompts/triage.py` — LLM prompt for 6-dimension scoring
- Output: `OpportunityScore` list + loaded `RepoRegistry` available in run context

## Dependencies

- **Depends on:** `infra-bootstrap` (schemas, config, auth), `pipeline-ingestion` (HeadlineCandidate list)
- **Blocks:** `pipeline-evidence`, `pipeline-implementation`

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:**
- Delegate a prompt-design subagent if the 6-dimension scoring prompt requires calibration against the fixture newsletter.
- RepoRegistry loader is independent of the scoring logic; can be implemented in a parallel session.

**Phase gates:**
- Scoring formula unit tests must pass before integrating with the LLM extraction step.
- Do not mark this plan complete until a fixture run through the full triage stage produces a ranked `OpportunityScore` list with correct `recommended_depth` values.

**Delegation triggers:**
- Calibrating dimension weights against real outputs → delegate a calibration subagent after first successful run.

**Verification:** `pytest tests/test_triage.py` passes; end-to-end fixture test produces ranked list with `recommended_depth` values matching ADR-0010 thresholds.

## TODOs

### Group 1: RepoRegistry loader (ADR-0007)

- [ ] Implement `load_registry(path: str = "repo-registry.yaml") -> RepoRegistry` in `src/tldr_ops/registry.py`: reads the YAML file, validates it with `RepoRegistry.model_validate(...)`, raises `RegistryError` with path and validation details if invalid. Acceptance: loading a valid `repo-registry.yaml` returns a `RepoRegistry`; loading a YAML with an unknown `allowed_actions` value raises `RegistryError`.
- [ ] Implement `get_repo(registry: RepoRegistry, name: str) -> RepoEntry`: returns the entry matching `name`, raises `RegistryError("Repo '{name}' not in registry")` if not found. Acceptance: looking up an existing repo returns its entry; looking up a non-existent repo raises `RegistryError`.
- [ ] Implement `check_action_permitted(entry: RepoEntry, action: Literal["analyze","write","prototype"]) -> None`: raises `PermissionError` if `action` not in `entry.allowed_actions`. Acceptance: checking `write` against an analyze-only entry raises `PermissionError`; checking `analyze` passes.

### Group 2: Scoring formula (ADR-0010)

- [ ] Implement `compute_score(dimensions: dict[str, float], weights: dict[str, float]) -> float` in `src/tldr_ops/triage.py`: weighted additive formula (`sum(w * d for w, d in zip(weights, dimensions))`); `complexity_cost` dimension uses its weight as a penalty (the weight value in config is already negative). Acceptance: given the ADR-0010 default weights and all dimensions at 0.5, score equals `0.5 * sum(abs(weights))` (computed).
- [ ] Implement `assign_depth(score: float, thresholds: dict[str, float]) -> Literal["skim","medium","deep"]`: maps score to depth using `thresholds["deep"]` (≥) and `thresholds["medium"]` (≥). Accepts `depth_override` map for per-candidate overrides. Acceptance: score 0.80 → `"deep"`; score 0.60 → `"medium"`; score 0.30 → `"skim"`; override map respected.
- [ ] Implement `compute_confidence_flag(dimensions: dict[str, float], reasoning: dict[str, str]) -> bool`: returns `True` (low confidence) if any single dimension has no reasoning string or if fewer than 2 dimensions have supporting evidence keywords in their reasoning. Acceptance: all empty reasoning strings → `low_confidence=True`; rich reasoning on all dimensions → `low_confidence=False`.

### Group 3: LLM prompt + dimension extraction

- [ ] Design the triage scoring prompt in `src/tldr_ops/prompts/triage.py`: system prompt instructs the LLM to rate a headline on 6 dimensions (project_relevance, actionability, novelty, credibility, upside, complexity_cost), each 0.0–1.0, with a required one-sentence reasoning per dimension. Output must be JSON. Acceptance: prompt constant defined; it explicitly lists the 6 dimensions and requires confidence evidence per dimension.
- [ ] Implement `score_candidate(candidate: HeadlineCandidate, config: RunConfig, openai_client) -> OpportunityScore` in `triage.py`: calls the LLM with the scoring prompt, parses the 6-dimension JSON response, computes `total_score` via `compute_score`, assigns `recommended_depth`, sets `low_confidence`, and returns `OpportunityScore`. Acceptance: with mocked OpenAI returning valid dimension JSON, function returns a fully populated `OpportunityScore`.
- [ ] Enforce scoring prompt to use the active `config.scoring_weights` in the prompt context (so the LLM knows which dimensions matter most). Acceptance: if weights are overridden in config, the prompt includes the overridden values in its instructions.

### Group 4: Stage runner + artifact output

- [ ] Implement `run_triage_stage(run_dir: Path, candidates: list[HeadlineCandidate], config: RunConfig, openai_client, registry: RepoRegistry) -> list[OpportunityScore]` in `stages/02_triage.py`: scores all candidates concurrently (using `asyncio.gather` or sequential with early stop), sorts by `total_score` descending, truncates to `config.top_n`, writes `OpportunityScore` list to `run_dir/02-triage/opportunity-scores.json` + digest `.md`. Returns ranked list. Acceptance: produces valid artifact file; `top_n` cap respected.
- [ ] Implement stop condition: if no candidate clears the `skim` threshold (all scores < `thresholds["medium"]`), write `no_opportunities_found: true` in the stage artifact and return empty list. Acceptance: all-low-score input triggers stop condition.
- [ ] Log the weights and thresholds used in the stage artifact header for reproducibility (RunManifest will reference them). Acceptance: artifact JSON includes `scoring_weights_used` and `depth_thresholds_used` fields.

### Group 5: Tests

- [ ] Write `tests/test_triage.py`: unit tests for `compute_score` (formula correctness), `assign_depth` (threshold boundaries), `compute_confidence_flag`, `load_registry`, `get_repo`, `check_action_permitted`. Mock LLM calls. Acceptance: `pytest tests/test_triage.py -v` passes all tests.
- [ ] Add `tests/fixtures/opportunity-scores-sample.json`: a fixture `OpportunityScore` list (3 items, mix of skim/medium/deep scores) for use in downstream stage tests. Acceptance: file loads and validates against `OpportunityScore` schema.
