# Automated discovery, research, and implementation pipeline

This repository holds **TLDR Research Ops** planning and automation assets, plus an in-repo **CICD** gate framework for pull requests.

## Start here

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Repository layout, workflows, and how the pieces fit together |
| [docs/prd/tldr-research-ops.prd.md](docs/prd/tldr-research-ops.prd.md) | Product goals, artifacts, and constraints |
| [docs/setup.md](docs/setup.md) | Local setup, env vars, and branching notes |
| [AGENTS.md](AGENTS.md) | Cursor secrets model, CICD judges, and agent conventions |
| [.cursor/automations/tldr-reader-ultra-lean/README.md](.cursor/automations/tldr-reader-ultra-lean/README.md) | TLDR Reader automation (UI, Playwright, or GitHub Actions fallback) |
| [docs/cicd/README.md](docs/cicd/README.md) | CICD pipeline overview (dogfooded under `cicd/`) |

## Quick checks

```bash
# TLDR automation files and spec consistency
sh scripts/validate-tldr-reader.sh

# CICD self-tests (installer, gates, judges, scaffolder)
bash cicd/tests/run-tests.sh
```

## Repository

Default remote: `https://github.com/hhalperin/automated-discovery-research-implementation-pipeline`
