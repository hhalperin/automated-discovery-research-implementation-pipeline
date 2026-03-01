---
planId: tldr-research-ops
title: "TLDR Research Ops — Root Plan"
parentPlanId: null
childPlanIds:
  - adr-finalization
  - infra-bootstrap
  - pipeline-ingestion
  - pipeline-triage
  - pipeline-evidence
  - pipeline-learning
  - pipeline-implementation
  - pipeline-codegen
  - ops-evaluation
---

# TLDR Research Ops — Root Plan

## References

- PRD: [docs/prd/tldr-research-ops.prd.md](../../docs/prd/tldr-research-ops.prd.md)
- ADRs:
  - [ADR-0001: Execution & Scheduling Strategy](../../docs/adr/ADR-0001-execution-scheduling.md)
  - [ADR-0002: Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
  - [ADR-0003: Auth, Secrets, and Least-Privilege Access Model](../../docs/adr/ADR-0003-auth-secrets-least-privilege.md)
  - [ADR-0004: Newsletter Ingestion Approach](../../docs/adr/ADR-0004-newsletter-ingestion.md)
  - [ADR-0005: Artifact Storage Strategy](../../docs/adr/ADR-0005-artifact-storage.md)
  - [ADR-0006: Safety Gates for Codegen / PR Creation](../../docs/adr/ADR-0006-safety-gates-codegen.md)
  - [ADR-0007: RepoRegistry Design](../../docs/adr/ADR-0007-repo-registry.md)
  - [ADR-0008: Evaluation & Feedback Loop](../../docs/adr/ADR-0008-evaluation-feedback.md)
  - [ADR-0009: Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)
  - [ADR-0010: Triage Scoring Algorithm & Depth Policy](../../docs/adr/ADR-0010-triage-scoring.md)
- Orchestrator prompt: [docs/guides/orchestrator-prompt.md](../../docs/guides/orchestrator-prompt.md)

## Vision

An AI pipeline that turns a morning TL;DR newsletter email into a ranked set of opportunities, then for top opportunities produces:
1. An **EvidencePack** (canonical sources + extracted claims + unknowns)
2. A **LearningPlan** (depth-configurable; "learn enough to decide")
3. An **ImplementationPlan** mapped to allowlisted GitHub repos
4. Optionally a **CodexExecutionBrief** for a safe prototype PR

### Non-negotiable invariants
- Dual-plan model: LearningPlan and ImplementationPlan are separate artifacts and stages.
- Evidence-gated reasoning: no downstream-impacting conclusions without an EvidencePack; uncertainty must be explicit.
- Artifact-first pipeline: every stage emits schema-validated artifacts with human-readable digest.
- Default is read-only: codegen/PR creation disabled unless explicitly enabled and human-approved.
- Repo allowlist enforced: only repos in RepoRegistry may be analyzed or targeted.
- No secrets in repo: all tokens live in secret stores, rotation-ready.
- Cost/time controls: top-N cap, depth policy, fetch caps, retries, stop conditions.

## Workstreams (index)

- [adr-finalization](./adr-finalization.plan.md) — Bootstrap: finalize all 10 ADRs before orchestrator run (**complete**)
- [infra-bootstrap](./infra-bootstrap.plan.md) — P1: Python package scaffolding + all cross-cutting infra modules (schemas, config, auth, storage, CI)
- [pipeline-ingestion](./pipeline-ingestion.plan.md) — P2: FR1 + FR2: newsletter ingestion, dedup, HeadlineCandidate extraction
- [pipeline-triage](./pipeline-triage.plan.md) — P3: FR3: opportunity scoring (ADR-0010 weighted additive) + RepoRegistry loading
- [pipeline-evidence](./pipeline-evidence.plan.md) — P4: FR4: source discovery, claim extraction, EvidencePack (evidence gate)
- [pipeline-learning](./pipeline-learning.plan.md) — P5: FR5: depth-calibrated LearningPlan + LearningDigest
- [pipeline-implementation](./pipeline-implementation.plan.md) — P6: FR6 + FR7: RepoFitAssessment + ImplementationPlan (dual-plan + allowlist)
- [pipeline-codegen](./pipeline-codegen.plan.md) — P7: FR8: safety gates + CodexExecutionBrief (default disabled)
- [ops-evaluation](./ops-evaluation.plan.md) — Ops: feedback loop, metrics (M1–M5), regression harness (ADR-0008)

## Execution strategy

This root plan is the entry point for the planning orchestrator. When running the orchestrator:

**Executor role:** Planning orchestrator (Cursor agent in Agent mode).

**Subagent fan-out:**
- Phase 1 discovery runs up to 4 subagents in parallel (docs audit, `.cursor/` audit, code inventory, product framing; then pipeline schemas, scheduling, auth, evaluation).
- Phase 2 synthesis runs up to 4 delegated synthesis subagents before any plan writing begins.
- Phase 3 plan-writing launches one subagent per child plan file (up to 4 in parallel).
- Phase 4 graph/registry update: one subagent.
- Phase 5 verification: one verification subagent; fix errors before finalizing.

**Phase gates:**
- Phase 1 → Phase 2: All 8 Phase 1 discovery subagents must return successfully (no missing outputs, no blocked todos). If a subagent fails or returns blocked items, re-launch or fix before proceeding.
- Phase 2 → Phase 3: Plan catalog (Phase 2C output) must be finalized with all required fields (planId, file path, parentPlanId, scope, dependencies). Do not begin plan writing until catalog is complete.
- Phase 3 → Phase 4: All plan files in the catalog must exist and pass basic structure validation (YAML frontmatter, TODOs, execution strategy section) before graph/registry update.
- Phase 4 → Phase 5: `plan-graph.yaml` and `registry.yaml` must be updated with consistent node entries before verification.
- Do not finalize without verification (Phase 5) passing.

**Phase gate failure handling:**
- If a Phase 1 subagent fails: re-launch with a narrower, targeted prompt. Do not proceed to Phase 2 with gaps.
- If Phase 2 synthesis subagents conflict materially: launch a reconciliation subagent (Phase 2B) before finalization.
- If Phase 5 verification finds errors: fix in-place before declaring the orchestration run complete.

**Nested subagents:** allowed in Phase 3 plan-writing if a workstream has complex sub-decomposition.

**Delegation triggers:**
- Synthesizing 3+ subagent reports → delegate to a synthesis subagent.
- Resolving contradictions across docs/code/plans → delegate to a reconciliation subagent.
- Any substantial design decision (schemas, auth posture, artifact contracts) → delegate first.

**TodoWrite requirement:** every multi-step subagent must start with TodoWrite and track completed/pending/blocked throughout.

See [docs/guides/orchestrator-prompt.md](../../docs/guides/orchestrator-prompt.md) for the full orchestrator prompt.

## Decision sequencing

ADR decisions must be finalized in this order before running the planning orchestrator. Each group has a dependency on the previous.

| Order | ADRs | Rationale |
|-------|------|-----------|
| 1 | ADR-0002 (schemas) | Blocks all artifact-producing stages; schema choice drives storage layout and evaluation replay |
| 2 | ADR-0001 + ADR-0003 | Scheduling determines secrets store; decide together to break circular dependency |
| 3 | ADR-0005 + ADR-0008 | Storage layout must be settled before evaluation/replay strategy can be finalized |
| 4 | ADR-0006 + ADR-0007 | Safety gates require the RepoRegistry allowlist model to be defined first |
| 5 | ADR-0009 + ADR-0010 | Cost/time controls and triage scoring must be defined before implementation planning |
| 6 | ADR-0004 | Newsletter ingestion scheduling can be finalized once ADR-0001 (scheduling) is decided |

See also: [docs/.cursor/plans/adr-finalization.plan.md](./adr-finalization.plan.md) for the bootstrap meta-plan that sequences ADR decisions.

## TODOs

<!-- Root-level orchestration TODOs only: plan catalog maintenance, verification, graph/registry consistency. -->
<!-- Child workstream TODOs belong in their respective plan files. -->

- [x] Finalize all ADR decisions following the decision sequencing table above before running the planning orchestrator. All 10 ADRs are Status: Accepted.
- [x] Run planning orchestrator (see docs/guides/orchestrator-prompt.md) to populate child plans. All 8 workstream child plans created; plan-graph.yaml and registry.yaml updated.
- [x] Confirm ADR decisions are recorded (Status: Accepted) for all 10 ADRs before implementation begins. All 10 ADRs are Status: Accepted.
- [x] Validate non-negotiable invariants are encoded in at least one child plan's acceptance criteria each. See invariant coverage below.
- [x] Review open questions in PRD section 10 and resolve or defer to specific child plans. All 3 open questions resolved or deferred.
- [x] Resolve PRD §10 open question: which TL;DR variants are in scope initially. Decision: TLDR AI only for MVP (ADR-0004).
- [x] Resolve PRD §10 open question: artifact storage location (planning repo vs same repo vs object storage). Decision: same repo gitignored (ADR-0005).
- [ ] Resolve PRD §10 open question: preferred review UX (GitHub issue, PR comment, or local dashboard). Deferred to ops-evaluation plan TODO (Group 5).
