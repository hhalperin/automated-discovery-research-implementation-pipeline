# CACD — Continuous Agent / Continuous Development

CACD is a drop-in CI pipeline that enforces quality and revertability on
**agent-authored branches**. It does **not** deploy anything.

## Why CACD exists

Autonomous agents (Cursor cloud agents, Codex, bots) open many small
branches and PRs. Without structure you get:

- Duplicate / overlapping work across branches.
- Huge, un-reviewable diffs that cannot be cleanly reverted.
- Documentation that drifts out of sync with code.
- Stale branches accumulating on the remote.
- Silent regressions — nothing asked "is this a net improvement?".

CACD answers all of those with a single opinionated quality loop.

## Components at a glance

| Layer | Lives in | Responsibility |
|-------|----------|----------------|
| CLI | `cacd/bin/cacd` | One entrypoint, subcommands. |
| Deterministic gates | `cacd/lib/checks/` | Exit 0/1, emit JSON. |
| LLM judges | `cacd/lib/judges/` | Emit verdict JSON (advisory). |
| Aggregator | `cacd/lib/report.sh` | Render sticky PR comment + labels. |
| Branch hygiene | `cacd/lib/branch-cleanup.sh` | Prune merged stale branches. |
| Revert helper | `cacd/lib/revert.sh` | Open a revert PR on demand. |
| Reusable workflows | `cacd/templates/workflows/*.yml` | Installed into `.github/workflows/`. |
| New-repo scaffolder | `cacd/lib/new-repo.sh` | First-class brand-new-repo path. |

See [install.md](./install.md), [config.md](./config.md), [judges.md](./judges.md),
and [new-repo.md](./new-repo.md).

## The quality loop

```
PR opened / synchronized
        │
        ▼
┌──────────────────────┐        ┌──────────────────────┐
│ Deterministic gates  │──fail─►│ Sticky comment + label│
│ (branch, size, docs, │        │  cacd/failing         │
│  revertability, ...) │        └──────────────────────┘
└──────────┬───────────┘
           │ pass
           ▼
┌──────────────────────┐
│    LLM judges        │  (improvement, quality, docs-accuracy)
│    verdicts → JSON   │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│  Aggregator          │  .cacd/out/report.md → sticky PR comment
│  + labels            │  .cacd/out/labels.txt → GH labels
└──────────────────────┘
```

Scheduled side-loop:

```
cron daily → cacd cleanup-branches → prune merged stale branches
                                   → label /cacd-stale on aging PRs
```

On-demand:

```
PR comment: /cacd revert <sha>  →  cacd/revert workflow → draft revert PR
```

## Contract between checks / judges and the pipeline

Every check writes `.cacd/out/checks/<name>.json`:

```json
{
  "kind": "check",
  "name": "size-cap",
  "status": "pass|fail|warn|skipped",
  "summary": "<one-line human summary>",
  "details": { "...": "check-specific" }
}
```

Every judge writes `.cacd/out/judges/<name>.json`:

```json
{
  "kind": "judge",
  "name": "quality",
  "status": "pass|warn|fail|skipped",
  "summary": "...",
  "details": {
    "verdict": "improvement|neutral|regression|pass|advisory|fail|skipped",
    "score": 0.83,
    "rationale": "...",
    "suggestions": ["..."],
    "backend": "openai|cursor-agent|stub"
  }
}
```

The aggregator consumes only these JSON files; adding a new check or
judge is a one-file change with zero glue code.

## Non-goals

- **No deployment.** CACD stops at the branch. Use your existing CD
  separately.
- **No long-lived server.** Everything runs on GitHub Actions runners
  and your local shell.
- **No repo-language lock-in.** Gates are pattern-driven; hooks are
  whatever command you configure.
