# ADR-0007: RepoRegistry Design

Status: Accepted
Date: 2026-02-24

## Context

ImplementationPlans must only reference repos that the user has explicitly allowlisted (FR6, G4). The RepoRegistry is the source of truth for: which repos are permitted, what actions are allowed per repo (analyze/write/prototype), the stack and constraints, goals, and integration surfaces. The registry design must be simple to maintain manually and machine-readable for pipeline consumption.

## Decision

**A1: YAML file `repo-registry.yaml` in repo root**, with Pydantic validation at pipeline startup (ADR-0002).

**Registry schema (per entry):**
```yaml
repos:
  - name: "tldr"                          # short identifier used in ImplementationPlans
    url: "https://github.com/harri/tldr"
    local_path: "C:/Users/harri/Documents/Coding Projects/fun/tldr"  # optional
    allowed_actions:                       # enum: analyze | write | prototype
      - analyze
      - prototype
    stack:
      - Python
      - Pydantic
    constraints:
      - "No breaking changes to public schemas without migration script"
    goals:
      - "Automate newsletter triage and research planning"
    integration_surfaces:
      - "src/tldr_ops/schemas/ — artifact schema package"
      - "config/run-config.yaml — runtime configuration"
```

- `allowed_actions` determines which token scope is loaded (ADR-0003) and which safety gates apply (ADR-0006).
- `analyze` — read-only GitHub API access; no write operations.
- `write` — can create branches and commits; requires `GITHUB_WRITE_PAT`.
- `prototype` — can create draft PRs; requires `GITHUB_WRITE_PAT` + `codegen_enabled: true`.
- Pipeline validates `repo-registry.yaml` against its Pydantic model at startup; invalid registry aborts the run.

## Alternatives considered

- **A1 (chosen)**: Human-editable; version-controlled; Pydantic validates schema at runtime.
- **A2 (JSON)**: Deferred. YAML is more readable for manual maintenance; Pydantic handles schema validation without needing a separate JSON Schema.
- **A3 (GitHub API-driven)**: Rejected. Loses explicit allowlist intent (any repo could be discovered); adds API dependency and implicit permission risk.
- **A4 (per-repo sidecar)**: Rejected. Requires write access to every target repo; impractical for repos not owned by the user.

## Consequences

- `repo-registry.yaml` committed at repo root; Pydantic `RepoRegistry` model validates it at startup.
- `RepoFitAssessment` artifact references the registry entry by `name`; ImplementationPlans only reference registered names.
- Token selection in `src/tldr_ops/auth.py` checks `allowed_actions` before loading write-scoped credentials.

## Notes / Follow-ups

- Implements FR6 (Repo allowlist + repo-fit) and G4 (Repo grounding).
- RepoFitAssessment is a downstream artifact that consumes the RepoRegistry; registry schema must expose all fields needed for fit scoring.
- Permitted actions must map to token scopes in ADR-0003 (read-only analysis vs write for PR creation).
