# ADR-0002: Artifact-First Pipeline & Schema-Validated Contracts

Status: Accepted
Date: 2026-02-24

## Context

Every pipeline stage must emit a structured, schema-validated artifact (not just logs or ad-hoc dicts). This ensures traceability, reproducibility, and safe handoffs between stages. The system defines 10 core artifact types (HeadlineCandidate through RunManifest/AuditLog). A schema versioning and validation approach must be selected and enforced consistently.

## Decision

**A2: Pydantic v2 models** for all 10 core artifact types, with JSON Schema export for documentation.

- Every artifact is a Pydantic `BaseModel` subclass with a `schema_version: Literal["1.0"]` field.
- Pydantic handles runtime validation, serialization (`.model_dump(mode="json")`), and auto-generates JSON Schema for contracts.
- All artifacts are serialized to `.json` on disk; a human-readable `.md` digest accompanies each.
- Schema versioning: `schema_version` is a literal string on every model. A migration script is required before bumping to "2.0". The `RunManifest` records the `schema_version` of all artifacts in the run.

## Alternatives considered

- **A1: JSON Schema only** — portable but requires manual schema authoring and a separate validation library; adds maintenance burden with no benefit for a Python-only pipeline. Deferred — JSON Schema exports are generated *from* Pydantic models rather than written by hand.
- **A2: Pydantic v2 (chosen)** — tight runtime validation; IDE auto-complete; `.model_dump()` / `.model_validate()` reduce boilerplate; Python-only is acceptable (pipeline is Python throughout MVP and production).
- **A3: Informal conventions** — rejected; violates the artifact-first non-negotiable invariant and makes replay/regression impossible.

## Consequences

- A `src/tldr_ops/schemas/` package holds all Pydantic model definitions, one module per artifact type.
- A `scripts/export_schemas.py` script generates `docs/schemas/{artifact}.schema.json` from each model; this is the documentation-facing contract.
- Every pipeline stage import is type-checked against its output model before writing to disk.
- Schema version bumps require a migration script and a changelog entry.

## Notes / Follow-ups

- Implements NFR1 (Traceability) and NFR2 (Reproducibility).
- Stage diagram and artifact contract table to be produced during planning Phase 1 (Pipeline stages & artifact schema agent).
- Schema versioning strategy must be decided to support replay and regression tests (see ADR-0008).
- Depends on ADR-0005 (Artifact Storage Strategy): the storage layout determines the directory structure, file naming, and versioning approach for artifact files on disk. Schema decisions and storage layout must be co-designed.
- Depends on ADR-0009 (Cost & Time Controls): the `RunConfig` snapshot and per-stage cost fields must be defined as part of the `RunManifest` artifact schema.
