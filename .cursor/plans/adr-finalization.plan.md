---
planId: adr-finalization
title: "ADR Finalization — Bootstrap Meta-Plan"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# ADR Finalization — Bootstrap Meta-Plan

## Purpose

This plan sequences the finalization of all 10 ADRs before the planning orchestrator is run. All ADRs are currently Status: Proposed with TBD decisions. The orchestrator (Phase 2 synthesis) cannot produce valid workstream plans until the architecture decisions that block it are resolved.

This plan must complete before running the orchestrator prompt in [docs/guides/orchestrator-prompt.md](../../docs/guides/orchestrator-prompt.md).

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- PRD: [docs/prd/tldr-research-ops.prd.md](../../docs/prd/tldr-research-ops.prd.md)
- ADRs:
  - [ADR-0001](../../docs/adr/ADR-0001-execution-scheduling.md)
  - [ADR-0002](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
  - [ADR-0003](../../docs/adr/ADR-0003-auth-secrets-least-privilege.md)
  - [ADR-0004](../../docs/adr/ADR-0004-newsletter-ingestion.md)
  - [ADR-0005](../../docs/adr/ADR-0005-artifact-storage.md)
  - [ADR-0006](../../docs/adr/ADR-0006-safety-gates-codegen.md)
  - [ADR-0007](../../docs/adr/ADR-0007-repo-registry.md)
  - [ADR-0008](../../docs/adr/ADR-0008-evaluation-feedback.md)
  - [ADR-0009](../../docs/adr/ADR-0009-cost-time-controls.md)
  - [ADR-0010](../../docs/adr/ADR-0010-triage-scoring.md)

## Decision sequencing rationale

ADRs have inter-dependencies. Deciding out of order forces rework. The sequence below minimizes backtracking:

```
ADR-0002 (schemas)
    └── ADR-0005 (storage) ─────────────────┐
    └── ADR-0009 (cost/time controls)        ├── ADR-0008 (evaluation)
    └── ADR-0010 (triage scoring)            │
                                             │
ADR-0001 (scheduling) ──────────────────────┤
    └── ADR-0003 (auth/secrets)              │
        └── ADR-0006 (safety gates) ─────────┤
            └── ADR-0007 (repo registry)     │
                                             │
ADR-0004 (ingestion) ──────── depends on 0001┘
```

## Execution strategy

**Executor role:** Owner (Halpy) working in a single focused session per ADR group. Each group is a natural decision unit.

**Subagent fan-out:** Use up to 2 parallel subagents per group to research alternatives and produce decision proposals. The owner arbitrates and writes the final decision.

**Phase gates:**
- Do not start Group 2 until ADR-0002 is Status: Accepted.
- Do not start Group 3 until ADR-0001 and ADR-0003 are Status: Accepted.
- Do not start Group 4 until all prior groups are Status: Accepted.
- Do not run the planning orchestrator until all 10 ADRs are Status: Accepted.

**Delegation triggers:**
- Any ADR requiring research into tooling options → delegate a research subagent to compare alternatives.
- Any ADR with circular dependency → resolve by drafting both simultaneously in the same session.

**TodoWrite requirement:** Use TodoWrite at the start of each ADR finalization session to track per-ADR status.

**Nested subagents:** allowed for research within a group (e.g., compare Pydantic vs JSON Schema for ADR-0002).

## TODOs

### Group 1: Schemas (blocks everything else)

- [x] Finalize ADR-0002: select schema format (JSON Schema vs Pydantic vs hybrid) and define schema versioning strategy. Decision: Pydantic v2 models with `schema_version: Literal["1.0"]` field; JSON Schema exported from Pydantic for docs.

### Group 2: Scheduling + Auth (circular; resolve together)

- [x] Finalize ADR-0001: select execution environment (local scheduler vs GitHub Actions cron) and define trigger mechanism. Decision: MVP = manual CLI invocation; production = GitHub Actions cron + workflow_dispatch.
- [x] Finalize ADR-0003: define secrets store (OS keystore vs GitHub Actions secrets), token scope table, and rotation strategy. Decision: keyring (Windows Credential Manager) for local; GitHub Actions secrets for CI; fine-grained PAT with separate read/write tokens.
- [x] Finalize ADR-0009: select cap enforcement model (config file + env var override recommended) and define RunConfig schema fields. Decision: A4 — `config/run-config.yaml` + `TLDR_` env var overrides; RunConfig fields and hard ceiling / soft cap distinction defined.
- [x] Finalize ADR-0010: select scoring formula (weighted additive recommended) and define depth thresholds (provisional: 0.75 deep, 0.50 medium). Decision: A1 weighted additive (weights: relevance=0.30, actionability=0.20, novelty=0.15, credibility=0.15, upside=0.15, complexity_cost=-0.05) + B1 threshold-based depth (deep ≥ 0.75, medium ≥ 0.50).

### Group 3: Storage + Evaluation (storage first)

- [x] Finalize ADR-0005: define artifact storage location (planning repo subdirectory recommended for MVP), directory layout, retention policy, and cleanup strategy. Decision: `storage/runs/YYYY-MM-DD_HHmmss_{hash}/` gitignored in same repo; keep last 30 runs; per-stage subdirs with .json + .md digest.
- [x] Finalize ADR-0008: define evaluation/feedback capture UX and dataset/replay strategy. Decision: A1 — post-run CLI rating prompt → `feedback.yaml` per run; pytest regression tests against frozen fixtures in `tests/fixtures/`.

### Group 4: Safety + Registry (registry informs gates)

- [x] Finalize ADR-0007: define RepoRegistry schema (allowed_actions, stack, constraints, goals, integration surfaces) and registry file format. Decision: `repo-registry.yaml` at repo root; `allowed_actions` enum: analyze / write / prototype; validated by Pydantic at startup.
- [x] Finalize ADR-0006: define approval flow, branch strategy, acceptance checks, and rollback mechanism for Codex execution. Decision: config flag `codegen_enabled: false` (primary) + interactive CLI approval (secondary); branch naming `codex/auto/{slug}-{YYYYMMDD}`; rollback steps in CodexExecutionBrief.
- [x] Finalize ADR-0004: select ingestion path for MVP (manual paste) and define upgrade trigger for Gmail API. Decision: MVP = `input/newsletter.txt` file drop; Gmail API upgrade trigger = ≥ 5 consecutive manual runs; TLDR AI variant only for MVP; URL normalization + token-overlap deduplication.

### Completion gate

- [x] Confirm all 10 ADRs are Status: Accepted. All 10 ADRs updated to Status: Accepted with filled Decision sections.
- [x] Update registry.yaml and plan-graph.yaml to link this plan under the root plan. Already present in both files from planning orchestrator run.
- [ ] Run planning orchestrator after all ADRs are accepted. Acceptance: orchestrator Phase 5 verification passes with no ADR-related blockers.
