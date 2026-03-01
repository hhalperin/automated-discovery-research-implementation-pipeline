---
planId: infra-bootstrap
title: "Infrastructure Bootstrap — Project Scaffolding + Core Infra Modules"
parentPlanId: tldr-research-ops
childPlanIds: []
---

# Infrastructure Bootstrap — Project Scaffolding + Core Infra Modules

## References

- Root plan: [tldr-research-ops.plan.md](./tldr-research-ops.plan.md)
- PRD: [docs/prd/tldr-research-ops.prd.md](../../docs/prd/tldr-research-ops.prd.md)
- ADR-0001: [Execution & Scheduling Strategy](../../docs/adr/ADR-0001-execution-scheduling.md)
- ADR-0002: [Artifact-First Pipeline & Schema-Validated Contracts](../../docs/adr/ADR-0002-artifact-pipeline-schemas.md)
- ADR-0003: [Auth, Secrets, and Least-Privilege Access Model](../../docs/adr/ADR-0003-auth-secrets-least-privilege.md)
- ADR-0005: [Artifact Storage Strategy](../../docs/adr/ADR-0005-artifact-storage.md)
- ADR-0009: [Cost & Time Controls](../../docs/adr/ADR-0009-cost-time-controls.md)

## Purpose

Establish the complete project skeleton and all cross-cutting infrastructure modules that every pipeline stage depends on. Nothing in this plan implements a pipeline stage; it only creates the foundation that all stages import.

## Scope

- Python package scaffolding (`pyproject.toml`, `src/tldr_ops/`, entry point)
- Pydantic artifact schemas for all 10 core artifact types (ADR-0002)
- `RunConfig` model + config file loader with env var overrides (ADR-0009)
- Auth/secrets module using `keyring` locally, env vars in CI (ADR-0003)
- Storage layer: run directory creation, artifact write helpers, retention cleanup (ADR-0005)
- `.github/workflows/daily-run.yml` CI workflow skeleton (ADR-0001)
- `repo-registry.yaml` placeholder with schema validation at startup (ADR-0007)
- `config/run-config.yaml` default config file (ADR-0009)

## Dependencies

- **Depends on:** `adr-finalization` (all 10 ADRs accepted — prerequisite met)
- **Blocks:** all pipeline workstream plans

## Execution strategy

**Executor role:** Cursor agent in Agent mode, single session per TODO group.

**Subagent fan-out:**
- Each TODO group below can be tackled as a standalone agent session.
- TODOs within a group that touch separate files may be parallelized.
- Schema definitions (Group 2) should all be drafted before the storage and auth modules are finalized, since those modules import schema types.

**Phase gates:**
- Do not begin Group 3 (auth) until Group 2 (schemas) Pydantic models compile without errors.
- Do not begin Group 4 (storage) until `RunConfig` model is defined (Group 3 depends on `RunConfig` for secret-name lookups).
- Do not mark this plan complete until `python -m tldr_ops --help` runs without error from the repo root.

**Delegation triggers:**
- If Pydantic v2 migration quirks arise (e.g., `model_validator`, discriminated unions), delegate a research subagent to check Pydantic v2 docs.
- If CI workflow needs Actions secrets configuration details, delegate a subagent to research GitHub Actions best practices.

**Verification:** run `pytest tests/ -x --tb=short` after Groups 1–5 are complete; all tests must pass (even if only skeleton tests exist).

## TODOs

### Group 1: Project scaffolding

- [ ] Create `pyproject.toml` with `[project]` metadata, `[tool.setuptools]` src layout, and `[project.scripts]` entry point `tldr-ops = "tldr_ops.__main__:main"`. Acceptance: `pip install -e .` succeeds; `tldr-ops --help` prints usage.
- [ ] Create `src/tldr_ops/__init__.py` (version string only) and `src/tldr_ops/__main__.py` with a `main()` function and a `run` subcommand stub (argparse or click). Acceptance: `python -m tldr_ops run --help` prints usage without importing any unresolved modules.
- [ ] Create `tests/__init__.py` and `tests/conftest.py` (empty fixtures stub). Create `tests/fixtures/` directory with a `.gitkeep`. Acceptance: `pytest tests/ --collect-only` runs without errors.
- [ ] Create `storage/.gitkeep`. Add `storage/runs/` and `input/newsletter.txt` to `.gitignore`. Acceptance: `git status` does not show `storage/runs/` or `input/newsletter.txt` as untracked after creating them.
- [ ] Create `input/.gitkeep`. Acceptance: `input/` directory present; `input/newsletter.txt` is gitignored.

### Group 2: Pydantic artifact schemas (ADR-0002)

- [ ] Create `src/tldr_ops/schemas/__init__.py` that exports all model classes. Create one module per artifact type. Acceptance: `from tldr_ops.schemas import HeadlineCandidate, OpportunityScore, EvidencePack, LearningPlan, LearningDigest, RepoRegistry, RepoFitAssessment, ImplementationPlan, CodexExecutionBrief, RunManifest` succeeds in a Python shell.
- [ ] Implement `HeadlineCandidate` model: fields `id` (str), `title` (str), `url` (str | None), `source` (str | None), `extraction_confidence` (float 0–1), `schema_version: Literal["1.0"]`, `timestamp` (datetime). Acceptance: model validates and serializes to JSON; `schema_version` field present in output.
- [ ] Implement `OpportunityScore` model: fields `candidate_id` (str), `dimensions` (dict[str, float] — 6 keys), `dimension_reasoning` (dict[str, str]), `weights_used` (dict[str, float]), `total_score` (float), `recommended_depth` (Literal["skim", "medium", "deep"]), `low_confidence` (bool), `schema_version: Literal["1.0"]`, `timestamp` (datetime). Acceptance: model validates; `total_score` is computed or validated as in range 0–1.
- [ ] Implement `EvidencePack` model: fields `candidate_id` (str), `sources` (list of source objects with `url`, `title`, `claims` list, `confidence` float), `contradictions` (list[str]), `unknowns` (list[str]), `schema_version: Literal["1.0"]`, `timestamp` (datetime), `openai_usage` (dict with `prompt_tokens`, `completion_tokens`). Acceptance: model validates with nested source objects.
- [ ] Implement `LearningPlan` + `LearningDigest` models: `LearningPlan` has `candidate_id`, `depth` (enum), `sections` (list), `stop_conditions` (list[str]), `decision_checkpoints` (list[str]), `schema_version`, `timestamp`, `openai_usage`. `LearningDigest` has `candidate_id`, `summary` (str), `key_takeaways` (list[str]), `schema_version`, `timestamp`. Acceptance: both models validate.
- [ ] Implement `RepoRegistry` model: a wrapper containing `repos` (list of `RepoEntry` with `name`, `url`, `local_path` (str | None), `allowed_actions` (list of Literal["analyze","write","prototype"]), `stack` (list[str]), `constraints` (list[str]), `goals` (list[str]), `integration_surfaces` (list[str])). Acceptance: model validates; loading `repo-registry.yaml` via `RepoRegistry.model_validate(yaml.safe_load(...))` succeeds.
- [ ] Implement `RepoFitAssessment` + `ImplementationPlan` models. `RepoFitAssessment`: `candidate_id`, `repo_name` (str), `fit_score` (float), `fit_reasoning` (str), `recommended_integration_points` (list[str]), `schema_version`, `timestamp`, `openai_usage`. `ImplementationPlan`: `candidate_id`, `repo_name`, `options` (list with `label`, `tasks`, `dependencies`, `acceptance_criteria`, `rollout_steps`, `rollback_steps`), `schema_version`, `timestamp`, `openai_usage`. Acceptance: both validate.
- [ ] Implement `CodexExecutionBrief` model (gated artifact): `candidate_id`, `repo_name`, `branch_name` (str), `diff_summary` (str), `tests_to_run` (list[str]), `acceptance_criteria` (list[str]), `rollback_steps` (list[str]), `approved_by` (str | None), `schema_version`, `timestamp`. Acceptance: model validates.
- [ ] Implement `RunManifest` model: `run_id` (str), `started_at` (datetime), `finished_at` (datetime | None), `exit_reason` (Literal["completed","stop_condition_triggered","error"]), `config_snapshot` (dict), `artifact_paths` (dict[str, str]), `openai_usage_total` (dict), `dedup_summary` (dict | None), `codegen_gate_result` (Literal["skipped","approved","rejected"] | None), `schema_version: Literal["1.0"]`. Acceptance: model validates.
- [ ] Create `scripts/export_schemas.py` that iterates all schema modules and writes `docs/schemas/{artifact_type}.schema.json` using `model.model_json_schema()`. Acceptance: running the script produces 10 JSON Schema files in `docs/schemas/`.

### Group 3: RunConfig + config loader (ADR-0009)

- [ ] Create `src/tldr_ops/config.py` with `RunConfig` Pydantic model (fields: `top_n: int = 5`, `depth_policy: Literal["skim","medium","deep","auto"] = "auto"`, `max_fetch_per_candidate: int = 3`, `max_tokens_per_run: int = 100_000`, `max_wall_seconds: int = 300`, `codegen_enabled: bool = False`, `retry_max: int = 2`, `retention_max_runs: int = 30`, `scoring_weights: dict[str, float]` with 6-key defaults, `depth_thresholds: dict[str, float]` with `deep=0.75`, `medium=0.50`, `depth_override: dict[str, str] = {}`). Acceptance: `RunConfig()` instantiates with defaults; all field types validated by Pydantic.
- [ ] Implement `load_config(path: str | None = None) -> RunConfig` in `config.py`: reads `config/run-config.yaml` if it exists, then merges env vars prefixed `TLDR_` (e.g., `TLDR_TOP_N` overrides `top_n`). Acceptance: setting `TLDR_TOP_N=3` in env before calling `load_config()` returns a `RunConfig` with `top_n=3`; missing config file falls back to defaults without error.
- [ ] Create `config/run-config.yaml` with all default values documented via inline comments. Acceptance: file is valid YAML; `load_config("config/run-config.yaml")` returns `RunConfig` with expected defaults.
- [ ] Add hard-ceiling validation: a `model_validator` on `RunConfig` raises `ValueError` if `top_n > 20`, `max_fetch_per_candidate > 10`, `max_tokens_per_run > 500_000`, or `max_wall_seconds > 1800`. Acceptance: constructing `RunConfig(top_n=21)` raises a `ValidationError`.

### Group 4: Auth/secrets module (ADR-0003)

- [ ] Create `src/tldr_ops/auth.py` with `get_secret(key: str) -> str` that reads from `keyring.get_password("tldr-ops", key)` if keyring returns a value, else falls back to `os.environ[key]`. Raises `SecretNotFoundError` (custom exception) if neither source has the key. Acceptance: unit test using monkeypatching of keyring and os.environ confirms both code paths.
- [ ] Define secret key constants in `auth.py`: `SECRET_OPENAI_API_KEY = "OPENAI_API_KEY"`, `SECRET_GITHUB_READ_PAT = "GITHUB_READ_PAT"`, `SECRET_GITHUB_WRITE_PAT = "GITHUB_WRITE_PAT"`, `SECRET_GMAIL_OAUTH = "GMAIL_OAUTH_CREDENTIALS"`. Acceptance: constants importable; no actual secrets committed.
- [ ] Implement `require_write_token(config: RunConfig)` in `auth.py`: raises `PermissionError` with clear message if `config.codegen_enabled` is False but `get_secret(SECRET_GITHUB_WRITE_PAT)` is called. Acceptance: calling with `codegen_enabled=False` raises `PermissionError`; with `codegen_enabled=True` proceeds to keyring lookup.
- [ ] Add secret redaction middleware: `redact_secrets(text: str) -> str` function that replaces known loaded secret values with `[REDACTED]` in any string. Wire into the Python root logger as a `logging.Filter`. Acceptance: a log line containing an actual secret value is redacted before being written.

### Group 5: Storage layer (ADR-0005)

- [ ] Create `src/tldr_ops/storage.py` with `create_run_dir(base: str = "storage/runs") -> Path` that generates a run directory `YYYY-MM-DD_HHmmss_{8-char-hash}`, creates it on disk, and returns the `Path`. Acceptance: calling twice within one second produces two distinct paths.
- [ ] Implement `write_artifact(run_dir: Path, stage: str, artifact_type: str, data: BaseModel) -> Path` that writes `run_dir/{stage}/{artifact_type}.json` (pretty-printed JSON from `data.model_dump(mode="json")`) and a companion `.md` digest containing a human-readable summary. Acceptance: file is written; loading it back with `model.model_validate_json(path.read_text())` round-trips correctly.
- [ ] Implement `cleanup_old_runs(base: str = "storage/runs", keep_n: int = 30)` that lists run directories sorted by name (oldest first) and deletes all but the newest `keep_n`. Acceptance: given 35 run directories, exactly 5 are deleted; the 30 newest remain.
- [ ] Write a test in `tests/test_storage.py` that exercises create_run_dir, write_artifact, and cleanup_old_runs end-to-end using a tmp_path fixture. Acceptance: `pytest tests/test_storage.py` passes.

### Group 6: CI workflow + repo-registry placeholder (ADR-0001, ADR-0007)

- [ ] Create `.github/workflows/daily-run.yml`: a workflow triggered by `schedule: [{cron: "0 7 * * 1-5"}]` and `workflow_dispatch`; installs Python, runs `pip install -e .`, then `tldr-ops run --config config/run-config.yaml`. Acceptance: YAML is valid; workflow file parses without errors in a YAML linter.
- [ ] Create `repo-registry.yaml` at repo root with a single entry for this repo (`name: tldr`, `url: https://github.com/harri/tldr`, `allowed_actions: [analyze, prototype]`, `stack: [Python, Pydantic]`). Acceptance: `RepoRegistry.model_validate(yaml.safe_load(open("repo-registry.yaml")))` succeeds without validation errors.
- [ ] Add startup validation in `__main__.py`: load and validate `repo-registry.yaml` at startup; abort with a clear error if validation fails. Acceptance: corrupting `repo-registry.yaml` causes `tldr-ops run` to exit with a non-zero code and a validation error message.
