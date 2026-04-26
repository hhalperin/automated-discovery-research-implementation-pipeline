# Contributing to {{REPO_NAME}}

This repo uses **CICD** to guard every PR. See [`cicd/README.md`](./cicd/README.md).

## Before you open a PR

1. Branch name matches `^(cursor|feature|fix|chore|docs|adr)\/[a-z0-9][a-z0-9._-]*$`.
2. Run `./cicd/bin/cicd run` locally to catch failing gates.
3. Update docs alongside code, or declare `cicd: docs-skip <reason>` in the PR body.

## Tests & lint

Configure hooks in `.cicd/config.yaml` under `hooks.lint` and `hooks.tests`.
CI runs them on every PR.
