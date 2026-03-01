---
planId: pipeline-ingestion
title: "Pipeline: Ingestion — Newsletter Ingestion + Candidate Extraction"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Pipeline: Ingestion — Newsletter Ingestion + Candidate Extraction

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0004: [Newsletter Ingestion Approach](../../docs/adr/ADR-0004-newsletter-ingestion.md)
- ADR-0002: [Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
- ADR-0009: [Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)
- PRD FR1 (Newsletter ingestion), FR2 (Candidate extraction)

## Purpose

Implement the first two pipeline stages: reading a newsletter from a file, deduplicating its items, and extracting structured `HeadlineCandidate` artifacts via LLM.

## Scope

- `src/tldr_ops/ingestion.py` — file loader, validator, deduplicator (ADR-0004)
- `src/tldr_ops/stages/01_ingestion.py` — stage runner producing `HeadlineCandidate` list
- MVP ingestion: `input/newsletter.txt` file drop; Gmail API stub
- Deduplication: URL normalization + Jaccard title overlap
- Output: `HeadlineCandidate` artifact list written to `storage/runs/{run-id}/01-ingestion/`

## Dependencies

- **Depends on:** `infra-bootstrap` (schemas, storage, config, auth modules must exist)
- **Blocks:** `pipeline-triage`

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:** This workstream is small enough for a single session. Delegate an LLM prompt-design subagent if the extraction prompt for `HeadlineCandidate` requires multiple iterations.

**Phase gates:**
- Do not implement the LLM extraction step until the file-loading and dedup logic passes unit tests.
- Do not mark this plan complete until a real newsletter sample in `tests/fixtures/newsletters/` produces a non-empty `HeadlineCandidate` list in a test.

**Delegation triggers:**
- If prompt engineering for candidate extraction requires more than 2 iterations to produce clean structured output, delegate a prompt-design subagent.

**Verification:** `pytest tests/test_ingestion.py` passes; stage integration test with a fixture newsletter produces ≥ 1 `HeadlineCandidate`.

## TODOs

### Group 1: File loader + validator

- [ ] Implement `load_newsletter(path: str) -> str` in `src/tldr_ops/ingestion.py`: reads the file, validates it is non-empty (raises `IngestionError` if empty), and returns the raw text. Acceptance: loading a non-empty file returns text; loading an empty file raises `IngestionError` with a clear message.
- [ ] Implement `validate_freshness(path: str, last_run_timestamp: datetime | None) -> None`: warns (does not abort) if the file's mtime is older than 12 hours and a previous run exists. Acceptance: stale file logs a `WARNING`; fresh file passes silently.

### Group 2: Deduplication (ADR-0004)

- [ ] Implement `normalize_url(url: str) -> str` in `ingestion.py`: strips UTM params (`utm_*`), fragments, and trailing slashes; lowercases scheme and host. Acceptance: `normalize_url("https://example.com/foo?utm_source=tldr#section")` returns `"https://example.com/foo"`.
- [ ] Implement `jaccard_title_overlap(a: str, b: str) -> float`: tokenize both strings on whitespace + punctuation, compute Jaccard overlap. Acceptance: identical titles return 1.0; completely different titles return 0.0; near-duplicate titles return ≥ 0.8.
- [ ] Implement `deduplicate_candidates(items: list[dict]) -> tuple[list[dict], dict]`: applies URL normalization and title overlap (threshold 0.8) to remove duplicate items; returns `(deduplicated_items, dedup_summary)` where `dedup_summary` records how many items were removed and why. Acceptance: a list with 3 items where 2 are near-duplicates returns 2 items and a summary recording 1 removal.

### Group 3: LLM extraction → HeadlineCandidate

- [ ] Design the extraction prompt in `src/tldr_ops/prompts/ingestion.py`: a system prompt + user template that takes raw newsletter text and returns a JSON array of candidate objects (title, url, source, extraction_confidence). The prompt must request explicit confidence values and handle items with missing URLs gracefully. Acceptance: prompt text is defined as a module-level constant; it includes instructions to return JSON only.
- [ ] Implement `extract_candidates(text: str, config: RunConfig, openai_client) -> list[HeadlineCandidate]` in `src/tldr_ops/stages/01_ingestion.py`: calls the OpenAI API with the extraction prompt, parses the JSON response, validates each item against `HeadlineCandidate` model, and returns the list. Acceptance: with a mocked OpenAI response returning valid JSON, the function returns a list of `HeadlineCandidate` objects; invalid JSON from the model raises `ExtractionError` with the raw response logged.
- [ ] Enforce `top_n` cap: after extraction, sort by `extraction_confidence` descending and truncate to `config.top_n`. Acceptance: given 10 extracted candidates and `config.top_n=5`, exactly 5 are returned.
- [ ] Track `openai_usage` from the API response and attach it to the stage output. Acceptance: stage output includes `prompt_tokens` and `completion_tokens` from the OpenAI response object.

### Group 4: Stage runner + artifact output

- [ ] Implement `run_ingestion_stage(run_dir: Path, config: RunConfig, openai_client) -> list[HeadlineCandidate]` in `stages/01_ingestion.py`: orchestrates load → deduplicate → extract → write artifact. Writes `HeadlineCandidate` list to `run_dir/01-ingestion/newsletter-candidates.json` and companion digest `.md`. Returns the candidate list. Acceptance: function produces a valid JSON file; loading it back validates against the `HeadlineCandidate` schema.
- [ ] Implement stop condition: if deduplication reduces candidates to 0, write `stop_condition_triggered: true` to stage output and return empty list (caller will record this in RunManifest). Acceptance: feeding an all-duplicate newsletter triggers stop condition and returns empty list.

### Group 5: Gmail API stub + tests

- [ ] Add `load_newsletter_gmail(label: str, config: RunConfig) -> str` stub in `ingestion.py` that raises `NotImplementedError("Gmail API ingestion not yet implemented. Use file-drop path.")`. Acceptance: calling the stub raises `NotImplementedError` with that exact message; the file-drop path remains functional.
- [ ] Write `tests/test_ingestion.py`: test `normalize_url`, `jaccard_title_overlap`, `deduplicate_candidates`, and `load_newsletter` (using `tmp_path` for file creation). Mock `extract_candidates` to avoid OpenAI calls. Acceptance: `pytest tests/test_ingestion.py -v` passes all tests.
- [ ] Add a fixture newsletter in `tests/fixtures/newsletters/sample-tldr-ai.txt` with ≥ 5 realistic (synthetic) newsletter items including at least one URL-duplicate and one title near-duplicate. Acceptance: running `deduplicate_candidates` on the fixture removes ≥ 1 duplicate.
