# CACD — Continuous Agent Continuous Development

A universal, drop-in CI pipeline for **agent-authored branches**. It enforces
quality gates, LLM judge rubrics, docs-parity, and clean branch hygiene on
GitHub Actions — without ever deploying anything.

> CACD stands for *Continuous Agent / Continuous Development*. Not CD.
> Shipping to production is explicitly out of scope.

## Why

Autonomous agents open lots of branches and PRs. Without structure you get
duplicate work, ballooning diffs, stale branches, documentation rot, and
undoable merges. CACD is an opinionated quality loop:

```
agent pushes branch ─► CACD (deterministic gates) ─► CACD (LLM judges)
                           │                             │
                           ▼                             ▼
                       sticky PR comment + labels + revert helper
                           │
                           ▼
                scheduled branch-cleanup keeps main repo tidy
```

Design principles (Unix):

1. **Do one thing well.** Every check/judge is its own script with a
   documented JSON contract.
2. **Text streams.** Checks and judges read `stdin`/env, write JSON to
   `stdout`, logs to `stderr`, and exit non-zero only on *gate* failure.
3. **Composable.** The aggregator merges any number of check/judge JSON
   blobs. Adding a new check = drop a file into `cacd/lib/checks/`.
4. **No implicit state.** All config lives in `.cacd/config.yaml`. All run
   output lives in `.cacd/out/`.
5. **Portable.** Pure Bash + Python stdlib + `jq`. No framework lock-in.
   Runs on any repo language.

## Install

Existing repo:

```bash
# from your repo root
curl -fsSL https://raw.githubusercontent.com/<your-org>/<this-repo>/main/cacd/install.sh | bash
# or, from a clone of this repo:
path/to/cacd/install.sh /path/to/your/repo
```

New repo (first-class):

```bash
path/to/cacd/bin/cacd new-repo my-new-service \
    --language python \
    --owner my-org
```

See [`docs/cacd/`](../docs/cacd/README.md) for the full guide.

## Components

| Path | Purpose |
|------|---------|
| `bin/cacd` | Single CLI entrypoint. `cacd <subcommand>`. |
| `lib/checks/` | Deterministic gates. Exit 0/1 on pass/fail. Emit JSON. |
| `lib/judges/` | LLM-prompted judges. Always exit 0. Emit JSON with verdict. |
| `lib/report.sh` | Aggregate all JSON blobs → sticky PR comment + labels. |
| `lib/branch-cleanup.sh` | Prune merged branches, label stale agent PRs. |
| `lib/revert.sh` | Open a revert PR for a merged commit on demand. |
| `workflows/` | Reusable `workflow_call` workflows importable by any repo. |
| `templates/` | One-line caller workflow, `.cacd/config.yaml`, PR template, CODEOWNERS, new-repo scaffold. |
| `install.sh` | Idempotent installer for existing repos. |
| `tests/` | Bash + pytest tests for checks, judges, installer, scaffolder. |

## Gates (deterministic)

All gates live in `cacd/lib/checks/`. Each script is invoked with no
arguments and reads the following env vars:

| Env var | Meaning |
|---------|---------|
| `CACD_BASE_SHA` | Merge-base SHA (or `origin/main`). |
| `CACD_HEAD_SHA` | HEAD of the PR branch. |
| `CACD_PR_BODY_FILE` | Path to a file containing the PR body. |
| `CACD_BRANCH` | Name of the PR branch. |
| `CACD_CONFIG` | Path to `.cacd/config.yaml`. |

Default gates:

1. **branch-naming** — enforces `cursor/<slug>-<tag>` or configured pattern.
2. **size-cap** — fails if the PR exceeds `max_changed_lines` (default 800)
   or `max_changed_files` (default 50).
3. **revertability** — PR must be squash-revertable: single logical intent,
   ≤ `max_commits` commits (default 20), no unrelated vendor/lock-file
   churn without explicit opt-in.
4. **secrets** — regex scan for common token shapes; fails on any hit.
5. **doc-parity** — if code paths touched, `docs/` must be touched or the
   PR body must contain `cacd: docs-skip <reason>`.
6. **lint** — runs language hooks declared in `.cacd/config.yaml`.
7. **tests** — runs test hooks declared in `.cacd/config.yaml`.

## Judges (advisory or blocking)

Each judge lives in `cacd/lib/judges/` and produces:

```json
{
  "judge": "improvement",
  "score": 0.82,
  "verdict": "improvement",
  "rationale": "...",
  "suggestions": ["..."]
}
```

Default judges:

- **improvement** — is this change a net improvement over baseline?
- **quality** — style, testing, complexity rubric (0–1).
- **docs-accuracy** — do the docs still describe reality?

Judges default to **advisory**. Flip them to **blocking** in
`.cacd/config.yaml` once you trust them. When `OPENAI_API_KEY` / judge
backend is unavailable, judges emit `verdict: "skipped"` and never block.

## Output

Every run writes to `.cacd/out/`:

```
.cacd/out/
  checks/<name>.json
  judges/<name>.json
  report.md           # rendered sticky PR comment
  labels.txt          # one label per line
  summary.json        # machine-readable aggregate
```

## License

MIT.
