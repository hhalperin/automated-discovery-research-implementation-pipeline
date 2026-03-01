# TLDR Research Ops — PRD

Owner: Halpy
Status: Draft
Last Updated: 2026-02-24

## 1. Product statement

A scheduled AI pipeline that ingests a TL;DR newsletter email, identifies which items matter to my active projects, collects canonical evidence, generates a depth-configurable LearningPlan, then generates an ImplementationPlan mapped to allowlisted GitHub repos. Optionally, it produces a CodexExecutionBrief for a safe prototype PR.

## 2. Goals

G1. High-signal triage: produce a ranked top-N opportunity list with explicit confidence and reasons.
G2. Evidence-backed research: produce an EvidencePack for selected opportunities with canonical sources and explicit unknowns.
G3. Dual-plan outputs: produce a LearningPlan and a separate ImplementationPlan, both schema-validated.
G4. Repo grounding: ImplementationPlans only reference repos explicitly allowlisted and described in a RepoRegistry.
G5. Safe automation: scheduled runs with audit trails and human review gates before any code changes.
G6. Programmatic auth: token-based authentication for OpenAI/Codex, GitHub, and email ingestion; least privilege; rotation-ready.

## 3. Non-goals

N1. Autonomous shipping to production without explicit approval gates.
N2. "General web crawling" beyond configured sources/caps.
N3. Perfect personalization from day one; feedback-driven improvement is expected.
N4. Replacing Cursor; Cursor is for building the system, not the user-facing runtime.

## 4. Primary user stories

US1. Every morning, I see top 3–5 opportunities with clear reasons and confidence.
US2. For each selected opportunity, I can verify claims quickly via an EvidencePack.
US3. I can choose skim/medium/deep learning based on relevance/time.
US4. I get an ImplementationPlan that references real insertion points and constraints of my allowlisted repos.
US5. I can approve or reject any proposed codegen/PR creation.
US6. The system runs on a schedule locally (MVP) and in GitHub Actions (production).

## 5. Core artifacts (hard requirement)

- HeadlineCandidate
- OpportunityScore
- EvidencePack
- LearningPlan
- LearningDigest
- RepoRegistry
- RepoFitAssessment
- ImplementationPlan
- CodexExecutionBrief (optional; gated)
- RunManifest/AuditLog (always)

Each artifact must include: timestamp, inputs/config snapshot, confidence, and unknowns.

## 6. Functional requirements

### FR1 Newsletter ingestion
- MVP supports manual paste.
- Production supports label-based email ingestion (e.g., Gmail API read-only).
- Dedupe topics/links across the newsletter.

### FR2 Candidate extraction
- Convert newsletter content into HeadlineCandidate list with links and extraction confidence.

### FR3 Triage scoring
- Compute OpportunityScore across dimensions (project relevance, novelty, actionability, credibility, upside, complexity cost).
- Output ranked list + recommended depth.

### FR4 Source discovery + evidence
- Fetch canonical sources and extract claims with per-claim confidence.
- Record contradictions and unknowns explicitly.

### FR5 LearningPlan generation
- Generate LearningPlan based on EvidencePack + depth policy + time budget.
- Include stop conditions and decision checkpoints.

### FR6 Repo allowlist + repo-fit
- Maintain RepoRegistry with allowed actions (analyze/write/prototype), stack, constraints, goals, integration surfaces.
- Generate RepoFitAssessment and only then generate ImplementationPlans.

### FR7 ImplementationPlan generation
- Provide options (MVP/ideal), tasks, dependencies, acceptance criteria, rollout/rollback, validation plan.

### FR8 Codex execution (gated)
- Generate CodexExecutionBrief only when explicitly enabled.
- Codex modifications must be constrained: branch strategy, tests, acceptance checks.
- Default mode is plan-only; no code write.

### FR9 Storage + audit
- Store each run as files (structured + summary).
- Emit a RunManifest tracking stage success/fail, timings, and produced artifacts.

## 7. Non-functional requirements

NFR1 Traceability: every claim points to sources; every plan points to evidence.
NFR2 Reproducibility: schema-validated artifacts + config snapshot per run.
NFR3 Safety: secrets never in repo/logs; least privilege tokens; human review gates.
NFR4 Operability: clear logs, retry policy, cost caps, failure handling.
NFR5 Extensibility: add new newsletters/sources and new stages without rewriting the pipeline.

## 8. Success metrics

M1 Triage precision: user rates ≥2 of top-3 as "useful" on most days.
M2 Evidence quality: deep items include canonical sources and explicit unknowns.
M3 Plan usefulness: LearningPlans and ImplementationPlans are actionable (user-rated).
M4 Prototype yield: approved Codex briefs produce acceptable PR drafts without scope creep.
M5 Time saved: measured via baseline comparison / self-report.

## 9. Rollout phases

P1 Local MVP: manual ingestion + candidate extraction + triage + artifact storage.
P2 Evidence + LearningPlans.
P3 RepoRegistry + RepoFit + ImplementationPlans.
P4 Gated Codex briefs + prototype PRs.
P5 GitHub Actions scheduling + operational hardening + evaluation loop.

## 10. Open questions

- Which TL;DR variants are in scope initially (AI/Tech/etc.)?
- Gmail API vs forwarding vs manual paste for early stages?
- Where do artifacts live long-term (planning repo vs same repo vs object storage)?
- Preferred review UX: GitHub issue, PR comment, or local dashboard?
