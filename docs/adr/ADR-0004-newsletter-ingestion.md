# ADR-0004: Newsletter Ingestion Approach

Status: Accepted
Date: 2026-02-24

## Context

The pipeline must reliably ingest TL;DR newsletter content. MVP needs a quick start (manual paste) without external API dependencies. Production needs a scheduled, automated ingestion path. Deduplication of topics/links across the newsletter body is required (FR1).

## Decision

**A1: Manual file drop for MVP.** Gmail API (A2) upgrade trigger defined.

**MVP ingestion:**
- Input file: `input/newsletter.txt` — user pastes newsletter content here before running the pipeline.
- Alternatively: `tldr-ops run --newsletter-file path/to/newsletter.txt`
- Pipeline validates file is non-empty and newer than the last run; aborts with a clear error if stale or missing.

**TL;DR variant in scope (PRD §10 open question):** TLDR AI only for MVP. Multi-variant support (TLDR Tech, TLDR DevOps, etc.) deferred until Gmail API is enabled and labels can discriminate per variant.

**Gmail API upgrade trigger:** Upgrade from A1 to A2 when the user has manually run the pipeline ≥ 5 consecutive weekdays without Gmail automation. A TODO is added to the RunManifest to prompt the upgrade.

**Deduplication strategy:**
- URL normalization: strip UTM params and fragments; use canonical URL as key.
- Title deduplication: token overlap ≥ 0.8 (Jaccard on word tokens) flags a duplicate.
- Duplicates logged in `RunManifest.dedup_summary`; not processed further.

## Alternatives considered

- **A1 (chosen for MVP)**: Zero external deps; gets first runs in immediately.
- **A2 (Gmail API, deferred to production)**: Required for scheduled runs without manual intervention; OAuth2 credentials stored via ADR-0003 strategy when enabled.
- **A3 (email forwarding + webhook)**: Rejected. Adds external service dependency with no advantage over Gmail API for a single-user tool.
- **A4 (RSS/web scrape)**: Rejected. TL;DR does not have a public RSS feed for the personalized email variant; scraping would miss subscriber-only content.

## Consequences

- `input/newsletter.txt` added to `.gitignore`.
- `src/tldr_ops/ingestion.py` handles file read, validation, deduplication.
- Gmail API path stubbed as `NotImplementedError` in MVP; upgrade path documented in `docs/guides/gmail-api-setup.md` (to be written when triggered).

## Notes / Follow-ups

- Implements FR1 (Newsletter ingestion).
- Must handle multiple TL;DR variants (AI, Tech, etc.) — open question in PRD section 10.
- Deduplication strategy must handle overlapping items across same-day newsletters.
- Depends on ADR-0001 (Execution & Scheduling Strategy): the scheduling mechanism determines how automated ingestion is triggered in production (cron vs workflow_dispatch) and where ingestion credentials are stored.
