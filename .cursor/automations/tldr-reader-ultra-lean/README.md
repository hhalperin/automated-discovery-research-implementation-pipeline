# TLDR Reader — Ultra-Lean Digest

A Cursor Automation that runs daily, scans TLDR Tech for high-leverage ideas matching your repos, and creates GitHub issues only when justified.

## Quick start

1. **Create the automation** at [cursor.com/automations/new](https://cursor.com/automations/new)
2. **Name:** TLDR Reader - Ultra-Lean Digest
3. **Trigger:** Schedule → Cron `0 7 * * *` (7:00 AM daily). Set timezone to local if supported.
4. **Tools:** Enable Web fetch, Memory, GitHub (create issues), Slack (optional)
5. **Prompt:** Paste the contents of `prompt.md` into the automation prompt field
6. **Memory:** Point the automation to this repo's `.cursor/automations/tldr-reader-ultra-lean/memory/` directory (or configure MCP/file access so it can read/write these files)

## First-run bootstrap

If `codebase_registry.yaml` and `repo_summaries.yaml` are empty or low quality, the automation will ask you for:

- Repo list / GitHub org or repo links
- Short description of each repo (if needed)
- Slack destination (if using Slack for paid-idea notifications)

Then it builds the registry, summaries, and routing rules. It will not ask again unless the registry is missing or stale.

## Memory files

| File | Purpose |
|------|---------|
| `codebase_registry.yaml` | Repo directory: purpose, stack, domains, exclusions |
| `repo_summaries.yaml` | ~200-token summary per repo |
| `routing_rules.yaml` | Map idea themes → repos |
| `tldr_archive.yaml` | Rolling 14-day archive (auto-updated) |
| `evaluation_history.yaml` | Learning from past runs (auto-updated) |

Edit `codebase_registry.yaml`, `repo_summaries.yaml`, and `routing_rules.yaml` before first run to skip bootstrap. Schemas are in `memory/*.schema.json`.

## Scheduling

- **Cron:** `0 7 * * *`
- **Timezone:** Use local if the platform supports it; otherwise UTC (note offset in run log)

## Success criteria

A successful run either:
1. Creates 1–3 relevant GitHub issues for free/high-value ideas, or
2. Quietly concludes there was nothing worth acting on.

Zero-action days produce no Slack, no issues—only internal log/archive.

## Failure modes avoided

- Noisy issue spam
- Shallow summaries without action
- Duplicate ideas
- Irrelevant repo mapping
- Expensive model calls on weak candidates
- Re-processing archive duplicates
- Broad research rabbit holes
