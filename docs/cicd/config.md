# Configuring CICD

All configuration lives in `.cicd/config.yaml`. Anything not set falls
back to the defaults hard-coded into each check.

Top-level sections:

```yaml
checks:         # which gates run, and their tunables
judges:         # which judges run, which are blocking
hooks:          # shell commands the `lint` and `tests` gates execute
branch_cleanup: # scheduled branch hygiene settings
```

## Enabling / disabling gates

```yaml
checks:
  enabled: [branch-naming, size-cap, revertability, secrets, doc-parity, lint, tests]
```

Remove an entry to disable the gate.

## Branch naming

```yaml
checks:
  branch_naming:
    pattern: '^(cursor|feature|fix|chore|docs|adr)\/[a-z0-9][a-z0-9._-]*$'
    exempt: [main, master, develop]
```

## Size cap

```yaml
checks:
  size_cap:
    max_changed_lines: 800
    max_changed_files: 50
```

## Revertability

```yaml
checks:
  revertability:
    max_commits: 20
    vendored_patterns: [...]   # mixing these with source triggers a failure
    infra_patterns:    [...]
    docs_patterns:     [...]
```

Override per-PR via the PR body:

```
cicd: allow-mixed we intentionally bumped node_modules to fix CVE
```

## Doc-parity

```yaml
checks:
  doc_parity:
    code_patterns: ['\.py$', '\.ts$', '^src/']
    docs_patterns: ['^docs/', '^README', '\.md$']
```

Override per-PR:

```
cicd: docs-skip purely internal refactor, no API change
```

## Lint & tests (language hooks)

```yaml
hooks:
  lint:
    - "ruff check src tests"
    - "npm run lint --silent"
  tests:
    - "pytest -q"
    - "npm test --silent"
```

Each entry is a shell command. Any non-zero exit fails the gate.

## Judges

```yaml
judges:
  enabled: [improvement, quality, docs-accuracy]
  # Listed judges are promoted to blocking (fail on regression/fail):
  blocking: []
```

Set backend via env:

- `OPENAI_API_KEY` + optional `OPENAI_MODEL` (default `gpt-4o-mini`)
- or a `cursor-agent` CLI on PATH with `CURSOR_API_KEY`.

If no backend is available, judges emit `verdict: skipped` and never
block.

## Branch cleanup

```yaml
branch_cleanup:
  protect:          [main, master, develop, release]
  prefix_allowlist: [cursor/, feature/, fix/, chore/, docs/, adr/]
  stale_days:       14
```

The daily `cicd-cleanup.yml` workflow reads these.
