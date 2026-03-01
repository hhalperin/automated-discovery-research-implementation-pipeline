# ADR-0009: Cost & Time Controls

Status: Accepted
Date: 2026-02-25

## Context

The pipeline calls external APIs (OpenAI, GitHub, Gmail) and runs potentially long fetch/analysis chains. Without explicit caps, a single misconfigured run can exhaust tokens, hit rate limits, or run indefinitely. This ADR defines the enforcement model for the "cost/time controls" non-negotiable invariant stated in the root plan.

Controls must cover:
- OpenAI token spend per run
- Number of opportunities processed (top-N cap)
- Per-stage depth configuration (skim / medium / deep)
- External fetch budget (URLs per stage, retries, timeouts)
- Total wall-clock budget per run
- Stop conditions that allow early exit without producing partial/corrupt artifacts

Controls must be configurable without code changes, enforced at runtime, and surfaced in the RunManifest/AuditLog.

Dependencies: ADR-0001 (scheduling, which determines where config lives), ADR-0002 (artifact schema, which determines how caps are logged), ADR-0010 (depth policy feeds into per-run cost estimates).

## Decision

**A4: Combined config file (`config/run-config.yaml`) with env var overrides.**

- `config/run-config.yaml` defines all caps with documented defaults; committed to repo.
- Env vars prefixed `TLDR_` override any cap at runtime (e.g., `TLDR_TOP_N=3`).
- The fully resolved, merged config is snapshotted in `RunManifest.config_snapshot` for reproducibility.

**RunConfig fields (Pydantic model, ADR-0002):**

| Field | Default | Hard ceiling | Description |
|-------|---------|--------------|-------------|
| `top_n` | 5 | 20 | Max opportunities to score and process |
| `depth_policy` | `"auto"` | — | `skim`/`medium`/`deep`/`auto` (auto uses ADR-0010 thresholds) |
| `max_fetch_per_candidate` | 3 | 10 | Max URLs fetched per candidate in evidence stage |
| `max_tokens_per_run` | 100_000 | 500_000 | Total OpenAI tokens across all stages |
| `max_wall_seconds` | 300 | 1_800 | Total wall-clock budget; triggers graceful stop |
| `codegen_enabled` | `false` | — | Enables CodexExecutionBrief stage (ADR-0006) |
| `retry_max` | 2 | 5 | Max retries per stage; counts against fetch cap |

- **Hard ceiling ≠ soft cap**: soft cap triggers graceful stop with `stop_condition_triggered: true` in RunManifest; hard ceiling raises `HardCeilingExceededError` immediately.
- Stop conditions leave all previously-written artifacts in valid state; partial run is documented, not an error.

## Alternatives considered

### A1: Config-file driven caps (YAML/TOML run config)
A per-run config file (e.g., `config/run-config.yaml`) defines all caps. The pipeline reads it at startup, validates it against a schema, and enforces caps inside each stage. Values have documented defaults and hard maximums.

- Pros: Single source of truth; versionable; diffable; easy to audit.
- Cons: Requires a config schema and validation layer; easy to forget to update defaults.

### A2: Environment variables only
Caps live in environment variables (`TLDR_TOP_N=5`, `TLDR_MAX_TOKENS=50000`, etc.).

- Pros: Works natively in GitHub Actions; no config file parsing.
- Cons: No single snapshot of the config used per run; harder to version; coupling between secrets and non-secrets.

### A3: Hardcoded defaults with CLI overrides
Sensible defaults baked in; CLI flags override at invocation time. No config file.

- Pros: Simple for MVP.
- Cons: Poor auditability; overrides not logged unless explicit; difficult to reproduce runs.

### A4: Combined: config file with env var overrides (chosen)
Config file provides defaults and is committed alongside code. Environment variables can override any cap (useful in CI). The resolved, merged config is snapshotted in the RunManifest for reproducibility.

- Pros: Best of A1 and A2; fully auditable; reproducible; secrets stay separate from caps.
- Cons: Slightly more implementation surface than A1 alone.

## Consequences

- `RunConfig` Pydantic model defined in `src/tldr_ops/schemas/run_config.py`; loaded and validated at startup.
- `RunManifest.config_snapshot` stores the fully resolved config (post env-var merge) for every run.
- Each pipeline stage receives a `RunConfig` instance; checks its cap before proceeding; sets `stop_condition_triggered: true` in its artifact output if a cap is reached.
- Token counts tracked per-stage via an `openai_usage` field in each artifact (prompt_tokens, completion_tokens).
- A1, A2, A3 are superseded by A4; no standalone env-var-only or hardcoded-defaults path.

## Notes / Follow-ups

- Implements the "Cost/time controls" non-negotiable invariant from the root plan.
- Depends on ADR-0001 (scheduling/execution env determines where config is loaded from).
- Depends on ADR-0002 (artifact schemas determine how the config snapshot is stored).
- Feeds into ADR-0010 (depth policy is one axis of the cost model).
- The `RunManifest` should record: `top_n_cap`, `depth_policy`, `fetch_cap_per_stage`, `max_tokens_per_run`, `max_wall_seconds`, `stop_condition_triggered`, `actual_token_spend`, `actual_wall_seconds`.
- Cost runaway mitigation: consider a hard ceiling (never-exceed) distinct from the soft cap (warn and stop gracefully), so operator can distinguish budget overrun from runaway.
- Retry budget: retries must count against the fetch cap; exponential backoff must not bypass the wall-clock budget.
