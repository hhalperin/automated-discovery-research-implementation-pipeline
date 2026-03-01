# ADR-0010: Triage Scoring Algorithm & Depth Policy

Status: Accepted
Date: 2026-02-25

## Context

FR3 requires computing an `OpportunityScore` across six dimensions for each extracted headline candidate and producing a ranked top-N list with recommended depth. FR5 requires a depth policy that maps score/context to skim/medium/deep learning plans.

Neither the scoring formula, the dimension weights, nor the depth thresholds are currently specified. Without this, triage output is non-reproducible and cannot be meaningfully evaluated against success metric M1 (≥2 of top-3 rated "useful" on most days).

The scoring system must:
- Be deterministic and reproducible given the same inputs and config
- Expose weights and thresholds as config (not hardcoded) to allow tuning without code changes
- Produce confidence values alongside scores (not just a ranking)
- Feed into ADR-0009 cost/time controls (higher depth → higher cost)

Dependencies: ADR-0002 (schema for `OpportunityScore` artifact), ADR-0009 (depth policy drives fetch caps and token budget per opportunity).

## Decision

**A1 (weighted additive score) + B1 (threshold-based depth).**

**Scoring formula:**
```
score = 0.30*relevance + 0.20*actionability + 0.15*novelty + 0.15*credibility + 0.15*upside - 0.05*complexity_cost
```
Each dimension rated 0.0–1.0 by LLM with explicit reasoning string. Weights defined in `RunConfig` with the above as defaults.

**Depth thresholds (configurable in RunConfig):**

| Score | Depth | Pipeline stages triggered |
|-------|-------|--------------------------|
| ≥ 0.75 | deep | EvidencePack + deep LearningPlan + ImplementationPlan |
| 0.50 – 0.74 | medium | EvidencePack + medium LearningPlan; ImplementationPlan optional |
| < 0.50 | skim | Headline + summary only; no EvidencePack or plan |

`depth_policy: "auto"` in RunConfig uses these thresholds. User can override per-opportunity at review time via `depth_override` map.

**Confidence flag**: `low_confidence: true` when any single dimension score differs from the LLM's stated uncertainty by > 0.3, or when fewer than 2 of 6 dimensions have supporting evidence.

## Alternatives considered

### Scoring formula

#### A1: Weighted additive score (recommended starting point)
`score = w1*relevance + w2*novelty + w3*actionability + w4*credibility + w5*upside + w6*complexity_cost`

Where each dimension is rated 0.0–1.0 by the LLM with explicit reasoning, and weights are defined in run config (defaults provided).

- Default weights (provisional): relevance=0.30, novelty=0.15, actionability=0.20, credibility=0.15, upside=0.15, complexity_cost=-0.05 (negative because higher complexity cost is a penalty).
- Pros: Transparent; auditable; weights are tunable without code changes; each dimension produces a per-claim reason string.
- Cons: LLM dimension ratings are subjective; weights require calibration.

#### A2: Multi-factor ranking with no aggregation
Rank opportunities separately on each dimension; produce a Pareto frontier; present top-N from the frontier.

- Pros: Avoids arbitrary weighting; shows tradeoffs clearly.
- Cons: Much harder to produce a single ranked list; UX is complex; doesn't produce a single "confidence" value.

#### A3: Binary relevance filter + LLM rerank
First filter by a hard relevance threshold; then ask the LLM to rank survivors by overall opportunity quality.

- Pros: Simple; leverages LLM holistic judgment.
- Cons: Non-reproducible (LLM ranking is non-deterministic without temperature=0); no per-dimension traceability; harder to evaluate M1.

Chosen: A1 for reproducibility and traceability. LLM assigns per-dimension scores with explicit reasoning; weights are tunable.

### Depth policy

#### B1: Threshold-based (recommended)
Map `OpportunityScore` to depth using configurable thresholds:

| Threshold | Depth | Description |
|-----------|-------|-------------|
| score ≥ 0.75 | deep | Full EvidencePack + deep LearningPlan + ImplementationPlan |
| 0.50 ≤ score < 0.75 | medium | EvidencePack + medium LearningPlan; ImplementationPlan optional |
| score < 0.50 | skim | Headline + summary only; no EvidencePack or plan |

Thresholds are configurable in run config. User can override per-opportunity at review time.

- Pros: Deterministic; configurable; maps cleanly to cost tiers in ADR-0009.
- Cons: Threshold values need calibration; doesn't account for time budget.

#### B2: Time-budget allocation
Allocate a total time budget across opportunities proportionally by score. Higher-score items get more time.

- Pros: Respects total run budget; adaptive.
- Cons: Complex to implement; remaining budget depends on execution order; partial artifacts are harder to handle.

Chosen: B1 for simplicity and reproducibility; B2 deferred as a later enhancement.

## Consequences

- `OpportunityScore` Pydantic model (ADR-0002) includes: `dimensions` (dict of 6 float scores), `dimension_reasoning` (dict of 6 strings), `weights_used` (dict), `total_score` (float), `recommended_depth` (enum), `low_confidence` (bool).
- `RunConfig` exposes: `scoring_weights` (dict, 6 values), `depth_thresholds` (dict: `deep`, `medium`), `depth_override` (dict mapping candidate id → depth).
- `RunManifest` records the weights and thresholds used in each triage run.
- User feedback (ADR-0008) stores ratings per ranked opportunity; `recommended_depth` rated separately for M1 calibration.

## Notes / Follow-ups

- Implements FR3 (Triage scoring) and the depth policy component of FR5 (LearningPlan generation).
- Depends on ADR-0002 (schema for `OpportunityScore`) and ADR-0009 (cost controls gated on depth).
- The six scoring dimensions from the PRD: project relevance, novelty, actionability, credibility, upside, complexity cost.
- `complexity_cost` should be treated as a penalty (higher = worse), hence negative weight in additive formula.
- "Confidence" in the `OpportunityScore` should reflect uncertainty in the LLM dimension ratings, not just the score value. A high score with uncertain dimensions should carry low confidence.
- Stop condition for triage: if top-N candidates are exhausted and no opportunity clears the `skim` threshold, the run should emit a `no_opportunities_found` flag in the RunManifest rather than proceeding to evidence/learning stages.
- Calibration approach: store OpportunityScores alongside user feedback ratings from M1 tracking; use this dataset to tune weights in future iterations (connects to ADR-0008 evaluation loop).
