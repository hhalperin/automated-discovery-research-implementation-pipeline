---
planId: pipeline-evidence
title: "Pipeline: Evidence — Source Discovery + EvidencePack Generation"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Pipeline: Evidence — Source Discovery + EvidencePack Generation

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0002: [Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
- ADR-0009: [Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)
- PRD FR4 (Source discovery + evidence)

## Purpose

For each scored opportunity that clears the `skim` threshold (i.e., `recommended_depth` is `"medium"` or `"deep"`), fetch canonical sources, extract claims with per-claim confidence, record contradictions and unknowns, and produce a validated `EvidencePack` artifact. This stage is the evidence gate: no downstream conclusions (LearningPlan, ImplementationPlan) are drawn without a complete EvidencePack.

## Scope

- `src/tldr_ops/stages/03_evidence.py` — stage runner
- `src/tldr_ops/evidence.py` — source fetching, claim extraction, contradiction detection
- `src/tldr_ops/prompts/evidence.py` — LLM prompts for claim extraction + contradiction flagging
- Output: one `EvidencePack` per qualifying opportunity, written to `run_dir/03-evidence/`
- Fetch cap enforced: `max_fetch_per_candidate` from `RunConfig` (ADR-0009)

## Dependencies

- **Depends on:** `infra-bootstrap`, `pipeline-triage` (scored `OpportunityScore` list with `recommended_depth`)
- **Blocks:** `pipeline-learning`, `pipeline-implementation`

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:**
- Source fetching and claim extraction are independent per candidate — may parallelize with `asyncio.gather`.
- Delegate a prompt-design subagent if claim extraction quality is unsatisfactory after first iteration.

**Phase gates:**
- Fetch + parse logic must pass unit tests before LLM claim extraction is integrated.
- Do not mark this plan complete until an end-to-end test with a fixture candidate produces a valid `EvidencePack` with ≥ 1 source and explicit `unknowns`.

**Delegation triggers:**
- If web content parsing is unreliable across source types (HTML, PDFs, paywalled pages), delegate a research subagent to evaluate extraction libraries.

**Verification:** `pytest tests/test_evidence.py` passes; fixture test produces `EvidencePack` with non-empty `sources`, `unknowns`, and correct `schema_version`.

## TODOs

### Group 1: Source fetcher

- [ ] Implement `fetch_source(url: str, timeout_secs: int = 10) -> str` in `src/tldr_ops/evidence.py`: fetches the URL, strips HTML to plain text (using `httpx` + `BeautifulSoup` or `trafilatura`), returns the extracted text. Raises `FetchError` on HTTP error or timeout. Acceptance: fetching a live URL (in integration test) or a mocked response returns non-empty text; HTTP 404 raises `FetchError`.
- [ ] Enforce `max_fetch_per_candidate` cap: `fetch_sources(urls: list[str], config: RunConfig) -> list[tuple[str, str]]` fetches at most `config.max_fetch_per_candidate` URLs, respects `config.retry_max` with exponential backoff, and counts retries against the fetch cap. Acceptance: given 10 URLs and `max_fetch_per_candidate=3`, exactly 3 are attempted; a retry on URL #1 reduces remaining budget to 2.
- [ ] Implement URL discovery: `discover_source_urls(candidate: HeadlineCandidate, config: RunConfig, openai_client) -> list[str]` — ask the LLM to suggest up to `max_fetch_per_candidate` canonical source URLs for the candidate (arXiv, official blog, GitHub repo, paper page, etc.). Returns URL list. Acceptance: mocked LLM returning a 3-URL JSON array produces a list of 3 strings.

### Group 2: Claim extraction + contradiction detection

- [ ] Design claim extraction prompt in `src/tldr_ops/prompts/evidence.py`: system prompt instructs LLM to extract structured claims from source text with per-claim confidence (0–1) and a one-sentence citation. Output must be JSON array of `{claim, confidence, citation}`. Acceptance: prompt defined as constant; it requires JSON output and explicit confidence values.
- [ ] Design contradiction detection prompt: given two or more source texts, identify any contradictory claims. Output: JSON list of `{claim_a, claim_b, nature_of_contradiction}`. Acceptance: prompt defined as constant.
- [ ] Implement `extract_claims(source_text: str, candidate: HeadlineCandidate, config: RunConfig, openai_client) -> list[dict]`: calls claim extraction prompt, parses JSON response, validates structure. Acceptance: mocked LLM response produces parsed list; malformed JSON raises `ExtractionError`.
- [ ] Implement `detect_contradictions(sources: list[str], config: RunConfig, openai_client) -> list[str]`: only called if ≥ 2 sources are fetched. Returns list of contradiction description strings. Acceptance: mocked multi-source input produces a list (may be empty if no contradictions found).
- [ ] Implement `identify_unknowns(candidate: HeadlineCandidate, claims: list[dict], config: RunConfig, openai_client) -> list[str]`: ask LLM to identify what remains unknown or unverifiable given the extracted claims. Returns list of unknown description strings. At least one unknown must always be produced (even if it is "no major unknowns identified"). Acceptance: output is a non-empty list.

### Group 3: Stage runner + artifact output

- [ ] Implement `build_evidence_pack(candidate: HeadlineCandidate, opportunity: OpportunityScore, config: RunConfig, openai_client) -> EvidencePack` in `evidence.py`: orchestrates discover → fetch → extract → detect contradictions → identify unknowns → assemble `EvidencePack`. Acceptance: returns a validated `EvidencePack` with all required fields.
- [ ] Implement `run_evidence_stage(run_dir: Path, candidates: list[HeadlineCandidate], scores: list[OpportunityScore], config: RunConfig, openai_client) -> list[EvidencePack]` in `stages/03_evidence.py`: filters to `medium`/`deep` opportunities, calls `build_evidence_pack` for each (respecting wall-clock budget), writes each `EvidencePack` to `run_dir/03-evidence/{candidate-slug}-evidence.json` + digest `.md`. Acceptance: only `medium`/`deep` candidates get evidence packs; `skim` candidates are skipped.
- [ ] Enforce wall-clock budget: track elapsed seconds; if remaining budget drops below a safety margin (10% of `max_wall_seconds`), stop processing additional candidates and set `stop_condition_triggered: true`. Acceptance: with a very short `max_wall_seconds`, stage terminates early with stop condition flag.
- [ ] Track aggregate `openai_usage` across all LLM calls in this stage. Acceptance: stage output header includes `openai_usage_stage` field summing tokens across all candidates.

### Group 4: Tests

- [ ] Write `tests/test_evidence.py`: unit tests for `normalize_url` (already tested in ingestion), `fetch_source` (mocked httpx), `extract_claims` (mocked LLM), `detect_contradictions` (mocked), `identify_unknowns` (mocked). Acceptance: `pytest tests/test_evidence.py -v` passes.
- [ ] Add `tests/fixtures/evidence-sample.json`: a fixture `EvidencePack` for the first item in the fixture opportunity scores. Acceptance: file validates against `EvidencePack` schema.
