# ADR-0005: Artifact Storage Strategy

Status: Accepted
Date: 2026-02-24

## Context

Every pipeline run must produce structured artifacts stored in a consistent, discoverable layout. The storage strategy must support: run isolation, human-readable summaries alongside structured files, retention/cleanup, and replay for regression testing. The PRD lists an open question about long-term artifact location (same repo, separate planning repo, or object storage).

## Decision

**A1: Filesystem under `storage/runs/` in the same repo (gitignored), with A4 as supplemental in GitHub Actions.**

**Directory layout:**
```
storage/
  runs/
    YYYY-MM-DD_HHmmss_{8-char-hash}/   # run directory; hash = first 8 of sha1(run_id)
      run-manifest.json
      run-manifest.md                  # human-readable digest
      01-ingestion/
        newsletter-candidates.json     # HeadlineCandidate list
        newsletter-candidates.md
      02-triage/
        opportunity-scores.json        # OpportunityScore list
        opportunity-scores.md
      03-evidence/
        {candidate-slug}-evidence.json # EvidencePack per candidate
        {candidate-slug}-evidence.md
      04-learning/
        {candidate-slug}-learning.json # LearningPlan
        {candidate-slug}-learning.md
      05-implementation/
        {candidate-slug}-impl.json     # ImplementationPlan
        {candidate-slug}-impl.md
      feedback.yaml                    # populated after user review (ADR-0008)
  .gitkeep
```

- `storage/` is in `.gitignore`; only `storage/.gitkeep` is tracked.
- Run ID format: `YYYY-MM-DD_HHmmss_{hash}` — human-sortable, collision-resistant.
- **Retention policy**: keep last 30 run directories; cleanup runs automatically at pipeline start (before the new run directory is created). Configurable via `RunConfig.retention_max_runs` (default 30).
- **GitHub Actions (A4 supplement)**: upload the run directory as an Actions artifact with 30-day retention for CI runs. Not a replacement for local storage; local is the primary store.

## Alternatives considered

- **A1 (chosen)**: Zero infrastructure; immediately queryable; good for single-user MVP.
- **A2 (separate storage repo)**: Deferred. Adds complexity without MVP benefit; re-evaluate if storage exceeds 500 MB or multi-user access is needed.
- **A3 (object storage)**: Deferred. No infra dependency needed for single-user personal tool.
- **A4 (GitHub Actions artifacts, supplemental)**: Used only for CI run archiving, not as primary store.

## Consequences

- `.gitignore` entry: `storage/runs/`
- `src/tldr_ops/storage.py` handles run directory creation, artifact writing, and retention cleanup.
- `RunManifest.artifact_paths` records the relative path of every artifact written in a run.
- `tests/fixtures/` stores frozen newsletter samples and frozen artifact snapshots for replay (ADR-0008).

## Notes / Follow-ups

- Implements FR9 (Storage + audit) and NFR2 (Reproducibility).
- RunManifest must record artifact paths, stage results, and config snapshot for each run.
- Retention and cleanup policy required to prevent unbounded local storage growth.
- Replay strategy (frozen runs, sample newsletters) is prerequisite for ADR-0008 regression checks.
