# ADR-0008: Evaluation & Feedback Loop

Status: Accepted
Date: 2026-02-24

## Context

The pipeline's value depends on triage precision, plan usefulness, and prototype yield improving over time. Without a feedback loop, there is no signal to guide improvement. A lightweight feedback mechanism must be designed that does not require a separate service, captures ratings close to the point of use, and feeds back into a dataset for regression testing (replay strategy from ADR-0005).

## Decision

**A1: Local rating file with post-run CLI prompt.**

After each pipeline run the CLI displays a summary and prompts for ratings:
- **Triage quality** (1–5): "Were the top-N opportunities actually relevant?"
- **Plan usefulness** (1–5): "Were the LearningPlan / ImplementationPlan outputs actionable?"
- **Notes** (optional free text)

Ratings stored in `storage/runs/{run-id}/feedback.yaml`:
```yaml
run_id: "2026-02-26_073012_a1b2c3d4"
triage_quality: 4
plan_usefulness: 3
notes: "ADR-0002 opportunity was obvious; depth too shallow"
timestamp: "2026-02-26T07:35:00Z"
```

**Regression / replay strategy:**
- Frozen newsletter fixtures: `tests/fixtures/newsletters/{date}.txt` — committed sample newsletters.
- Frozen artifact snapshots: `tests/fixtures/runs/{date}/` — committed expected outputs for regression.
- Pytest parametrize replays frozen inputs through individual stages and diffs against expected outputs.
- Replay tests are non-destructive (write to `storage/runs/test-*/`; cleaned up after test).

**Metric collection (M1–M5):**
- `scripts/metrics.py` parses all `feedback.yaml` files and prints rolling averages per metric.
- M1 (triage precision): mean `triage_quality` ≥ 3 on ≥ 80% of days.

## Alternatives considered

- **A1 (chosen)**: Zero infra; file is version-controllable for trend review; trivial to parse.
- **A2 (GitHub issues)**: Deferred. Adds context-switching overhead; overkill for single-user personal tool.
- **A3 (PR comments)**: Deferred. Only applicable when codegen is enabled; doesn't cover planning-only runs.
- **A4 (dedicated service)**: Rejected. Over-engineered for single-user MVP.

## Consequences

- `src/tldr_ops/feedback.py` handles post-run rating prompt and `feedback.yaml` write.
- `tests/conftest.py` loads fixtures and parametrizes replay tests.
- `scripts/metrics.py` aggregates ratings across runs.
- Feedback files must not include secrets, PII, or newsletter content verbatim (summaries only).

## Notes / Follow-ups

- Implements M1–M5 (Success metrics) from the PRD.
- Dataset/replay strategy must store sample newsletters and frozen run snapshots for regression checks (links to ADR-0005).
- Metrics: triage precision, plan usefulness, prototype yield, time saved.
- Feedback data must not include secrets or personally sensitive content in stored artifacts.
