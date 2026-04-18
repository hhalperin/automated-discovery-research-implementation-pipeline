# {{REPO_NAME}}

> Scaffolded with [CICD](https://github.com/{{OWNER}}/cicd). Language: `{{LANGUAGE}}`.

## What this is

A starter {{LANGUAGE}} repo with [CICD](./cicd/README.md) preinstalled. CICD
enforces a quality loop on every PR: deterministic gates, LLM judges,
docs-parity, and scheduled branch cleanup. It does not deploy anything.

## Getting started

```bash
# Clone and init
git clone https://github.com/{{OWNER}}/{{REPO_NAME}}.git
cd {{REPO_NAME}}

# Read the CICD guide
open cicd/README.md
```

## Branch & PR model

- Default branch: `main`.
- Branches must match `^(cursor|feature|fix|chore|docs|adr)\/...` (see
  `.cicd/config.yaml`).
- PRs must respect the size cap and revertability gates.
- If your PR changes code, it should also update docs, or declare
  `cicd: docs-skip <reason>` in the PR body.

## Reverts

Comment `/cicd revert <sha>` on a merged PR, or run the `CICD Revert`
workflow manually. CICD opens a draft revert PR for you.
