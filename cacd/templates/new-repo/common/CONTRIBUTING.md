# Contributing to {{REPO_NAME}}

This repo uses **CACD** to guard every PR. See [`cacd/README.md`](./cacd/README.md).

## Before you open a PR

1. Branch name matches `^(cursor|feature|fix|chore|docs|adr)\/[a-z0-9][a-z0-9._-]*$`.
2. Run `./cacd/bin/cacd run` locally to catch failing gates.
3. Update docs alongside code, or declare `cacd: docs-skip <reason>` in the PR body.

## Tests & lint

Configure hooks in `.cacd/config.yaml` under `hooks.lint` and `hooks.tests`.
CI runs them on every PR.
