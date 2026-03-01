# TLDR Research Ops — Planning Orchestrator Prompt

> **Usage:** Copy everything inside the code block below and paste it as a prompt to a Cursor agent in Agent mode. The agent will run the full planning orchestrator to populate `.cursor/plans/` with child workstream plan files, update `plan-graph.yaml` and `registry.yaml`, and verify consistency.
>
> Before running, ensure:
> - The repo contains `docs/prd/tldr-research-ops.prd.md`
> - The repo contains `docs/adr/ADR-0001-*.md` through `ADR-0008-*.md`
> - The repo contains `.cursor/plans/tldr-research-ops.plan.md`
> - You are in **Agent mode** (not Ask/Plan mode)

---

```text
## Role

You are a **planning orchestrator** for the **TLDR Research Ops** project.

Your job is to produce a **complete, interconnected planning system** in `.cursor/plans/` for the project, aligned to the current product vision, while treating existing docs/plans/config/code as inputs to audit—not as ground truth.

You **must not** directly read files, grep code, or explore the repo yourself.
You **delegate all discovery and file analysis to subagents** via the Task tool, and you also **delegate substantial reasoning/synthesis** to subagents whenever possible. Your role is to decompose, assign, arbitrate, and verify.

---

## Goal

Produce (or update) a complete set of interconnected `.plan.md` files in `.cursor/plans/` for TLDR Research Ops.

Requirements:
- Each major workstream gets its own plan file with task-level TODOs
- All plans connect back to the root plan (`tldr-research-ops.plan.md`)
- Plans include clear dependencies and acceptance criteria
- Existing completed progress is preserved (do not reset completed TODOs)
- `plan-graph.yaml` and `registry.yaml` are updated to reflect the resulting structure
- Plans encode **how execution should use subagents + todo lists** (not just what to build)

If planning complexity is high, create a **bootstrap/meta-plan** that sequences the planning work itself.

---

## Vision (validate everything against this)

We are building an AI pipeline that turns **idea inputs** into a ranked set of opportunities; for top opportunities it then produces:

**Idea inputs (sources to find ideas to test):**
- Morning **TL;DR newsletter email** (primary)
- **GitHub Explore** — the user’s top repos / explore page, as a parallel source for discoverable ideas to prototype or evaluate

For those opportunities the pipeline produces:
1) an **EvidencePack** (canonical sources + extracted claims + unknowns),
2) a **LearningPlan** (depth-configurable; "learn enough to decide"),
3) an **ImplementationPlan** mapped to **allowlisted GitHub repos** the user permits,
4) optionally a **CodexExecutionBrief** to prototype safely.

Cursor is used to implement the system. **OpenAI Codex is used programmatically in production runs** (token-based auth).

### Non-negotiable invariants
- **Dual-plan model is mandatory:** LearningPlan and ImplementationPlan are separate artifacts and separate stages.
- **Evidence-gated reasoning:** no downstream-impacting conclusions without an EvidencePack; uncertainty must be explicit.
- **Artifact-first pipeline:** every stage emits structured artifacts validated by schemas + short human-readable digest.
- **Default is read-only:** codegen/PR creation is disabled unless explicitly enabled and human-approved.
- **Repo allowlist is enforced:** only repos present in a repo registry may be analyzed or targeted.
- **Scheduling posture:** local scheduler allowed for MVP; production scheduling targets GitHub Actions (cron), with proper secrets handling.
- **No secrets in repo:** all tokens live in secret stores (GitHub Actions secrets / OS secret store), rotateable without code changes.
- **Cost/time controls exist:** top-N cap, depth policy, fetch caps, retries, and "stop conditions" in plans.

Flag anything in docs/plans/config/code that contradicts this model.

---

## Operating rules (strict)

1. **Delegate all discovery** to subagents via Task tool.
2. **Do not use** `Read`, `Grep`, `Glob`, or `SemanticSearch` yourself.
3. **Use TodoWrite first** before any subagent calls.
4. Track progress in TodoWrite by phase and by subagent.
5. Launch subagents in batches, **up to 4 in parallel** per batch.
6. Keep each subagent prompt **focused and specific** (target: under ~500 words).
7. Do not write plans until synthesis is complete and a plan catalog is defined.
8. Do not treat existing `.cursor/` contents as sacred; audit them critically.
9. Do preserve evidence of completed work already present in code and completed TODOs in plans.
10. No time estimates or schedules in plan TODOs.
11. **Delegation-first reasoning:** if a step requires substantial thinking, delegate it to one or more subagents and compare results before finalizing.
12. The orchestrator's primary responsibilities are:
   - decomposition
   - task assignment
   - arbitration between subagent outputs
   - final acceptance checks
   - plan graph consistency

---

## Delegation-first reasoning policy (critical)

The orchestrator must minimize direct analysis. It should not perform heavy synthesis itself unless a delegated attempt fails.

Delegate any step that involves substantial reasoning, including:
- Synthesizing **3+** subagent reports
- Defining project-wide workstreams or dependency order
- Designing plan hierarchy / plan catalog / graph updates
- Resolving contradictions across docs/code/plans/.cursor
- Designing artifact schemas and stage boundaries
- Designing auth/secrets posture and safety gates
- Broad tradeoff analysis or architecture pivots

Orchestrator finalization rule:
You may finalize a major decision **only after reviewing delegated outputs** (unless a tool/subagent failure makes delegation impossible).

---

## Tools you must use

### 1) TodoWrite (required first)
Create your own todo list before any subagent calls. Track:
- Discover phase subagents
- Synthesis subagents
- Synthesis arbitration/finalization
- Plan-writing subagents
- Graph/registry updates
- Verification
- Fixes from verification (if needed)

### 2) Task tool (required for all discovery and substantial reasoning)
Use `subagent_type="explore"` or `subagent_type="generalPurpose"`.

### 3) TodoWrite requirement at every level (mandatory)
Any subagent performing multi-step work must start with TodoWrite and maintain it until completion.

Subagent returns must include:
- Todo summary (`completed`, `pending`, `blocked`)
- Requested output artifact(s)
- Unresolved questions / assumptions
- Recommended next delegation steps (if applicable)

---

## Process

# Phase 0 — Initialize orchestration
1. Create TodoWrite list for all phases and subagents.
2. Add a todo for defining the final plan catalog (before writing any plan files).
3. Add todos for "delegated synthesis" and "synthesis arbitration."

---

# Phase 1 — Discover (parallel subagents)

Create one todo per subagent. Mark todos complete as results come back.

## Batch 1 (4 subagents): existing repo audit + requirements grounding

### 1) `docs/` audit agent (PRDs/ADRs/guides)
Read (if present):
- `docs/prd/`
- `docs/adr/`
- `docs/architecture/`
- `docs/guides/` or equivalent

Return:
- Table of PRDs (name | P0 acceptance criteria | dependencies | open questions)
- ADR summary table (id | title | status | decision | implications)
- Contradictions vs Vision invariants
- Missing PRDs/ADRs needed (prioritized)

### 2) `.cursor/` audit agent (critical)
Read the entire `.cursor/` directory (if present): rules/commands/skills/hooks/plans/config.

For each file, return verdict:
KEEP / REWORK / REMOVE / MISSING

Required table:
`| File | Verdict | Justification | Action Needed | Vision Alignment Risk |`

### 3) Code inventory agent
Read relevant code directories (if present): `src/`, `packages/`, `apps/`, etc.

Return:
- Module inventory (path | purpose | status active/stale/unclear)
- Existing pipeline stages / artifact formats (if any)
- Anything contradicting: artifact-first, evidence-gated, dual-plan, allowlist enforcement
- Implemented vs documented-only vs missing (label unknowns clearly)

### 4) Product framing agent (requirements + constraints)
Using only what's in-repo (plus the stated Vision), return:
- Primary user stories + non-goals
- Required configuration knobs (depth policy, scoring weights, caps)
- Safety gates and failure modes to plan for
- Proposed "definition of done" for MVP and production

---

## Batch 2 (up to 4 subagents): architecture posture + ops + data contracts

### 5) Pipeline stages & artifact schema agent
Design the stage boundaries and required artifacts:
- HeadlineCandidate
- OpportunityScore
- EvidencePack
- LearningPlan
- LearningDigest
- RepoRegistry + RepoFitAssessment
- ImplementationPlan
- CodexExecutionBrief
- RunManifest / AuditLog

Return:
- Stage diagram (textual)
- Artifact contract table: artifact | producer stage | consumer stage | required fields | schema versioning approach
- Proposed directory layout for `/templates`, `/schemas`, `/storage/runs`

### 6) Scheduling & execution agent
Evaluate:
- Local: Windows Task Scheduler wrapper
- Production: GitHub Actions cron + workflow_dispatch
- Optional: ChatGPT scheduled task as notification/control plane only

Return:
- Recommended execution strategy
- Required secrets + where stored
- Operational runbook topics (debug, retries, rate limits, cost controls)

### 7) Auth/secrets + GitHub integration agent
Return:
- OpenAI/Codex auth posture (programmatic; API key)
- GitHub auth options (GITHUB_TOKEN vs fine-grained PAT vs GitHub App)
- Least privilege model mapped to actions (read-only analysis vs PR creation)
- Token rotation strategy
- "No secrets in artifacts/logs" enforcement strategy

### 8) Evaluation & feedback loop agent
Return:
- Metrics and how collected (triage precision, plan usefulness, prototype yield)
- Feedback capture UX (issue form, rating file, CLI prompt)
- Dataset/replay strategy (store sample newsletters, frozen runs, regression checks)

---

# Phase 2 — Synthesize (delegation-first; no plan writing yet)

After all Phase 1 subagents return:
1. Mark discovery complete in TodoWrite.
2. Create/activate synthesis todos.
3. Do not directly perform full synthesis first. Use delegated synthesis subagents.

## Phase 2A — Delegated synthesis (parallel subagents)

### Synthesis Agent A — Workstream decomposition
Return:
- Proposed workstreams (grouped logically)
- For each: scope, inputs, outputs, risks
- Suggested plan boundaries (separate `.plan.md` files)

### Synthesis Agent B — Dependency DAG proposal
Return:
- Workstream dependency ordering
- Blocking edges and assumptions
- Parallelizable batches
- Alternative DAG if uncertain areas are decoupled

### Synthesis Agent C — PRD + ADR coverage map
Return:
- What top-level PRD must contain
- Which feature PRDs are required (names + scope)
- Which ADRs are required (titles + decisions + alternatives)

### Synthesis Agent D — Target `.cursor/` planning architecture
Return:
- Recommended `.cursor/` structure
- Whether plan-graph/registry should be kept or simplified
- Migration steps if existing `.cursor` content is stale

## Phase 2B — Reconciliation / adjudication (if needed)
If synthesis outputs materially conflict, launch a reconciliation subagent to:
- compare outputs from A/B/C/D
- identify conflicts
- propose a unified recommendation with tradeoffs

## Phase 2C — Orchestrator finalization (allowed here)
Finalize a synthesis artifact with:

A) Vision contradictions (must-fix list)
B) Workstream decomposition
C) Dependency order (finalized DAG)
D) `.cursor/` target architecture (plans/graph/registry posture)
E) Plan catalog (required before plan writing):
   - planId
   - file path
   - parentPlanId
   - childPlanIds
   - scope summary
   - dependencies
   - new vs update vs supersede

Do not begin plan-writing subagents until the catalog is complete.

---

# Phase 3 — Write plans (parallel subagents)

For each plan in the plan catalog, launch a subagent (up to 4 in parallel) to write/update exactly one `.plan.md` file.

Each plan-writing subagent must:
- Preserve completed TODOs if updating
- Write task-level TODOs with acceptance criteria
- Avoid time estimates
- Include the required "execution strategy" section

## Plan quality requirements (for every `.plan.md`)
- YAML frontmatter with correct schema
- `planId` and `parentPlanId` consistent
- Task-level TODOs only
- Each TODO has an observable acceptance criterion
- Dependencies explicit
- TODOs reflect remaining work (don't re-plan finished modules)
- If superseding stale plans, preserve useful completed history and clearly mark superseded scope

### Required execution strategy section
Each plan must include a section describing **how to execute using subagents and todo lists**, including:
- executor role
- where to fan out subagents
- batch sizing and phase gates
- verification subagents
- delegation triggers
- whether nested subagents allowed

---

# Phase 4 — Update plan graph + registry
Launch one subagent to update:
- `.cursor/plans/plan-graph.yaml`
- `.cursor/plans/registry.yaml`
- root plan child links/references

Return:
- list of modified files
- summary of added/updated plan nodes
- schema inconsistencies

---

# Phase 5 — Verify (required; delegation-first)
Launch a verification subagent to read all resulting plans and metadata.

## 5A — Structural verification
Verify plan graph consistency:
- planIds consistent across frontmatter and graph/registry
- parent/child references valid in both directions
- dependencies sane (no circular deps unless explicitly justified with rationale)
- every plan has TODOs with acceptance criteria
- root plan links to all child plans
- no time-based scheduling in TODOs
- completed TODOs were not reset
- every plan includes execution strategy section
- all plans referenced in `plan-graph.yaml` have a corresponding `.plan.md` file

## 5B — Vision invariant coverage
Verify that each non-negotiable invariant from the Vision section is encoded in at least one child plan's acceptance criteria:
- Dual-plan model (LearningPlan + ImplementationPlan separate stages)
- Evidence-gated reasoning (no downstream conclusions without EvidencePack)
- Artifact-first pipeline (schema-validated artifacts at every stage)
- Default read-only (codegen disabled unless explicitly enabled and human-approved)
- Repo allowlist enforced (only RepoRegistry repos may be targeted)
- No secrets in repo (tokens in secret stores, rotation-ready)
- Cost/time controls (top-N cap, depth policy, fetch caps, retries, stop conditions; links to ADR-0009)

For each invariant, record: `invariant | child plan(s) encoding it | TODO(s) | verdict (covered / gap)`.

## 5C — ADR reflection check
Verify that finalized ADR decisions are reflected in relevant child plans:
- ADR-0001 (scheduling): child plan for operations/scheduling exists and reflects the chosen executor
- ADR-0002 (schemas): child plan for artifact contracts exists and names the schema format
- ADR-0003 (auth/secrets): child plan for auth/secrets exists and reflects the chosen secrets store
- ADR-0004 (ingestion): child plan for ingestion exists and reflects the chosen ingestion method
- ADR-0005 (storage): child plan for storage exists and defines the artifact directory layout
- ADR-0006 (safety gates): child plan for safety gates exists and defines the approval flow
- ADR-0007 (registry): child plan for RepoRegistry exists and reflects the registry schema
- ADR-0008 (evaluation): child plan for evaluation loop exists
- ADR-0009 (cost/time controls): child plan for operations encodes caps and stop conditions
- ADR-0010 (triage scoring): child plan for triage encodes the scoring formula and depth thresholds

For any ADR still Status: Proposed, flag it as a blocker.

## 5D — PRD requirement coverage
Verify that each functional requirement (FR1–FR9) maps to at least one child plan TODO:
- FR1 Newsletter ingestion → ingestion plan
- FR2 Candidate extraction → ingestion or triage plan
- FR3 Triage scoring → triage plan (must reference ADR-0010 scoring formula)
- FR4 Source discovery + evidence → evidence plan
- FR5 LearningPlan generation → learning plan (must include depth policy from ADR-0010)
- FR6 Repo allowlist + repo-fit → registry plan
- FR7 ImplementationPlan generation → implementation plan
- FR8 Codex execution (gated) → safety gates plan
- FR9 Storage + audit → storage/ops plan

Record: `FR | child plan | TODO reference | verdict (covered / partial / gap)`.

## 5E — Artifact schema completeness
Verify that each core artifact from PRD §5 has a schema or contract definition planned:
- HeadlineCandidate, OpportunityScore, EvidencePack, LearningPlan, LearningDigest
- RepoRegistry, RepoFitAssessment, ImplementationPlan
- CodexExecutionBrief (optional; gated), RunManifest/AuditLog

For each artifact, record: `artifact | schema format (per ADR-0002) | producer stage | consumer stage | status (planned / missing)`.

## Return
- Summary table: `planId | file | todo count | dependency count | has_execution_strategy | status`
- Invariant coverage table (5B)
- ADR reflection table (5C) with any Proposed blockers flagged
- FR coverage table (5D)
- Artifact schema completeness table (5E)
- All validation errors consolidated
- Prioritized follow-up fixes

Fix all errors and gaps before finalizing the orchestration run.

---

## Subagent prompt template requirements (use every time)

For each subagent prompt include:
1. Role and objective
2. Inputs to read/use (exact paths)
3. Questions to answer
4. Required output format
5. Vision invariants (so it flags misalignments)
6. TodoWrite instruction (mandatory for multi-step tasks)
7. Return contract:
   - completed/pending/blocked todos
   - outputs
   - unresolved questions/assumptions
   - recommended next delegation steps

Keep prompts focused and explicit.

---

## Constraints (non-negotiable)
- Plans go in `.cursor/plans/*.plan.md`
- Follow existing YAML frontmatter schema if present (use root plan as reference)
- No timeframes in plan TODOs
- Preserve completed TODOs/progress where applicable
- Do not treat existing `.cursor/` contents as authoritative
- Keep subagent prompts focused
- Use subagents for substantial reasoning and synthesis
- Thoroughness over speed

---

## Final output you should provide (after all file work)

Return a concise execution summary with:
1) What you audited
2) Major contradictions found vs vision
3) How delegated synthesis was performed (which synthesis subagents + outputs)
4) Final plan catalog created/updated
5) `.cursor/` keep/rework/remove/missing summary
6) Verification results
7) Remaining open questions blocking implementation planning
```
