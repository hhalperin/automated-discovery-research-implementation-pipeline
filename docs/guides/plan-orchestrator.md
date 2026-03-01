# Plan Orchestrator — Run Plans in Separate Contexts

The script `scripts/run-plans.py` runs each workstream plan in its own Cursor Agent invocation so each plan gets a **new context window**. That keeps context size manageable and enforces one plan per run.

## Prerequisites

- **Cursor Agent CLI** — the command is `agent` (install adds it to PATH).
  - Install: [Cursor CLI installation](https://cursor.com/docs/cli/installation)
    - Windows (PowerShell): `irm 'https://cursor.com/install?win32=true' | iex`
    - macOS/Linux: `curl https://cursor.com/install -fsS | bash`
  - Auth: set `CURSOR_API_KEY` or run `agent login`
- Run from the **tldr repo root** (the script checks for `.cursor/plans/`).

## Usage

```bash
# List plans in execution order
python scripts/run-plans.py --list

# Run a single plan (e.g. infra-bootstrap)
python scripts/run-plans.py --plan infra-bootstrap

# Run all plans in dependency order (one agent per plan; stop on first failure)
python scripts/run-plans.py --all

# Dry-run: print the agent commands without running them
python scripts/run-plans.py --all --dry-run
```

## Options

| Option | Description |
|--------|-------------|
| `--all` | Run all plans in dependency order. |
| `--plan PLAN_ID` | Run one plan (e.g. `infra-bootstrap`, `pipeline-ingestion`). |
| `--list` | List plan IDs and exit. |
| `--dry-run` | Print commands only; do not invoke the agent. |
| `--no-force` | Do not pass `--force` to the agent (changes proposed, not applied). |
| `--no-trust` | Do not pass `--trust` (may prompt in headless). |
| `--log-dir DIR` | Directory for per-plan logs (default: `.cursor/plan-logs/`). |
| `--no-log-dir` | Do not write log files; agent output to stdout/stderr. |
| `--agent-cmd CMD` | Override the agent binary (default: `agent`). |

## Execution order

Order is fixed in the script to match `.cursor/plans/plan-graph.yaml`:

1. infra-bootstrap
2. pipeline-ingestion
3. pipeline-triage
4. pipeline-evidence
5. pipeline-learning
6. pipeline-implementation
7. pipeline-codegen
8. ops-evaluation

`tldr-research-ops` (root) and `adr-finalization` (complete) are skipped.

## How it works

- Each plan is run by invoking **`agent`** with:
  `agent -p --force --trust --workspace <repo> "<prompt>"`
  The prompt tells the agent to read the plan file and implement all unchecked TODOs.
- Every run is a **new process**, so each plan gets a fresh context window.
- With `--all`, the script stops after the first plan that exits non-zero.
- Logs are written under `.cursor/plan-logs/<planId>.log` unless `--no-log-dir` is used.

## Overriding the agent command

Use `--agent-cmd` or `CURSOR_AGENT_CMD` only if `agent` is not on PATH (e.g. you need the full path to the binary).

## See also

- [Cursor headless CLI](https://cursor.com/docs/cli/headless)
- Root plan: `.cursor/plans/tldr-research-ops.plan.md`
- Plan graph: `.cursor/plans/plan-graph.yaml`
