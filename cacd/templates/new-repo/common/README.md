# {{REPO_NAME}}

> Scaffolded with [CACD](https://github.com/{{OWNER}}/cacd). Language: `{{LANGUAGE}}`.

## What this is

A starter {{LANGUAGE}} repo with [CACD](./cacd/README.md) preinstalled. CACD
enforces a quality loop on every PR: deterministic gates, LLM judges,
docs-parity, and scheduled branch cleanup. It does not deploy anything.

## Getting started

```bash
# Clone and init
git clone https://github.com/{{OWNER}}/{{REPO_NAME}}.git
cd {{REPO_NAME}}

# Read the CACD guide
open cacd/README.md
```

## Branch & PR model

- Default branch: `main`.
- Branches must match `^(cursor|feature|fix|chore|docs|adr)\/...` (see
  `.cacd/config.yaml`).
- PRs must respect the size cap and revertability gates.
- If your PR changes code, it should also update docs, or declare
  `cacd: docs-skip <reason>` in the PR body.

## Reverts

Comment `/cacd revert <sha>` on a merged PR, or run the `CACD Revert`
workflow manually. CACD opens a draft revert PR for you.
