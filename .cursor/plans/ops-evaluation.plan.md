---
planId: ops-evaluation
title: "Ops: Evaluation + Feedback Loop"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Ops: Evaluation + Feedback Loop

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- ADR-0008: [Evaluation & Feedback Loop](../../docs/adr/ADR-0008-evaluation-feedback.md)
- ADR-0005: [Artifact Storage Strategy](../../docs/adr/ADR-0005-artifact-storage.md)
- ADR-0010: [Triage Scoring Algorithm & Depth Policy](../../docs/adr/ADR-0010-triage-scoring.md)

## Purpose

Implement the feedback capture mechanism (post-run CLI rating prompt), metrics aggregation, and regression test harness. This workstream makes the pipeline improvable over time by capturing per-run user ratings and enabling systematic replay against frozen fixtures.

## Scope

- `src/tldr_ops/feedback.py` — post-run rating prompt + `feedback.yaml` write
- `scripts/metrics.py` — aggregate ratings across runs for M1–M5 metrics
- `tests/conftest.py` + `tests/test_regression.py` — regression/replay harness using frozen fixtures
- Output: `feedback.yaml` per run; `docs/metrics/` trend reports

## Dependencies

- **Depends on:** `infra-bootstrap` (storage, schemas, config)
- **Note:** Can be implemented in parallel with pipeline stages; does not depend on any specific stage being complete

## Execution strategy

**Executor role:** Cursor agent in Agent mode.

**Subagent fan-out:**
- Feedback module and regression test harness are independent; can be implemented in parallel subagent sessions.

**Phase gates:**
- Feedback module must complete before the end-to-end pipeline runner integrates post-run prompting.
- Regression tests require at least one fixture in `tests/fixtures/` to be meaningful.

**Delegation triggers:**
- If metrics aggregation logic is complex (trend analysis, rolling averages), delegate a data-analysis subagent.

**Verification:** `pytest tests/test_regression.py` passes with fixture data; `python scripts/metrics.py` runs without error and prints a metrics summary.

## TODOs

### Group 1: Post-run rating prompt (ADR-0008)

- [ ] Implement `prompt_for_feedback(run_id: str, scores: list[OpportunityScore]) -> dict` in `src/tldr_ops/feedback.py`: displays a summary of the top opportunities ranked in the run, then asks for: (1) `triage_quality` (1–5 int), (2) `plan_usefulness` (1–5 int, skipped if no plans generated), (3) `notes` (optional free text, Enter to skip). Returns a dict with these fields. Acceptance: function reads from `input()` correctly; non-integer inputs loop until valid; Enter on notes field sets `notes: null`.
- [ ] Implement `save_feedback(run_dir: Path, run_id: str, ratings: dict) -> Path` in `feedback.py`: writes `feedback.yaml` to `run_dir/feedback.yaml` with `run_id`, `timestamp`, and the rating fields. Acceptance: YAML file is written; loading it with `yaml.safe_load` returns the expected dict structure.
- [ ] Integrate feedback prompt into `__main__.py` pipeline runner: after all stages complete (or stop condition), call `prompt_for_feedback` and `save_feedback`. Skip if `--no-feedback` flag is passed. Acceptance: running `tldr-ops run` ends with a feedback prompt; `--no-feedback` skips it silently.
- [ ] Ensure feedback files contain no secrets, no verbatim newsletter content, and no LLM raw outputs. Acceptance: code review confirms only rating values, run_id, timestamp, and optional short note are written.

### Group 2: Metrics aggregation (ADR-0008, M1–M5)

- [ ] Implement `collect_feedback_records(storage_root: str = "storage/runs") -> list[dict]` in `scripts/metrics.py`: walks all run directories, finds `feedback.yaml` files, loads and parses each. Returns list of dicts sorted by timestamp. Acceptance: given 5 run dirs with feedback.yaml files, returns 5 records in chronological order.
- [ ] Implement `compute_metrics(records: list[dict]) -> dict` in `metrics.py`: computes rolling metrics:
  - M1 (triage precision): fraction of runs where `triage_quality >= 3`
  - M2 (plan usefulness): mean `plan_usefulness` across runs where it was rated
  - M3 (feedback coverage): fraction of runs that have a feedback.yaml
  - Includes trend: "last 7" vs "all-time" values for M1 and M2.
  Acceptance: given a fixture list of 10 records with known values, computed metrics match expected.
- [ ] Implement CLI output in `scripts/metrics.py`: `python scripts/metrics.py [--runs N]` prints a formatted metrics summary table to stdout. Acceptance: running the script on a fixture set of records prints a readable table without errors.
- [ ] Add a TODO comment in `metrics.py` for future weight-calibration: "TODO: once ≥ 20 rated runs are collected, compare `triage_quality` ratings against `OpportunityScore.total_score` to calibrate scoring weights (ADR-0010)." Acceptance: comment present; not a blocking implementation item.

### Group 3: Regression / replay test harness (ADR-0008)

- [ ] Define the fixture convention in `tests/conftest.py`: a `load_fixture(name: str)` helper that reads `tests/fixtures/{name}` and returns parsed JSON or text. Acceptance: `load_fixture("newsletters/sample-tldr-ai.txt")` returns the newsletter text string; `load_fixture("opportunity-scores-sample.json")` returns a list.
- [ ] Write `tests/test_regression.py`: parametrize tests over fixture inputs and expected outputs using `@pytest.mark.parametrize`. Initial regression test: given `tests/fixtures/newsletters/sample-tldr-ai.txt` and the ingestion + triage stages run with mocked LLM responses from `tests/fixtures/`, assert that output artifacts validate against their Pydantic schemas. Acceptance: `pytest tests/test_regression.py -v` passes; adding a new fixture pair auto-registers as a new test case.
- [ ] Document fixture format in `tests/fixtures/README.md`: explain the purpose of each fixture type, how to add new ones, and the naming convention. Acceptance: README exists; a new developer can follow it to add a newsletter fixture without reading source code.

### Group 4: RunManifest finalization integration

- [ ] Implement `finalize_run_manifest(run_dir: Path, manifest: RunManifest, feedback: dict | None) -> RunManifest` in `src/tldr_ops/storage.py`: updates `manifest.finished_at`, `manifest.exit_reason`, and (if feedback available) adds a `feedback_recorded: true` flag. Writes final `run-manifest.json` to `run_dir/`. Acceptance: manifest file written; loading it back validates against `RunManifest` schema with correct `finished_at`.
- [ ] Write `tests/test_manifest.py`: test that finalize_run_manifest produces a valid RunManifest with all required fields. Acceptance: `pytest tests/test_manifest.py -v` passes.

### Group 5: Unresolved PRD §10 question — review UX

- [ ] Decide on preferred review UX (GitHub issue, PR comment, or local dashboard) and record the decision. Options: (a) local terminal summary (already implemented via feedback prompt), (b) generate a `run-summary.md` in the run dir for manual review, (c) defer to a future enhancement. Acceptance: a decision is recorded in a new ADR or as a note in this plan; the open question in PRD §10 is closed.
