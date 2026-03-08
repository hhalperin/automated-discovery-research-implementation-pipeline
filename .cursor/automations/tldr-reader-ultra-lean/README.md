# TLDR Reader — Ultra-Lean Digest

A Cursor Automation that runs daily, scans TLDR Tech for high-leverage ideas matching your repos, and creates GitHub issues only when justified.

## Setup options

Cursor does not expose an API to create automations (UI only). Three ways to run this:

### Option A: Playwright UI automation (recommended for first-time setup)

Uses Playwright to fill the automation form at cursor.com/automations/new.

```bash
cd .cursor/automations/tldr-reader-ultra-lean/playwright
npm install && npm run setup
```

First run: log in when prompted, then the script fills name, prompt, cron, tools. Review and click Create. See `playwright/README.md` for details.

### Option B: GitHub Actions + Cloud Agents API

Uses the Cursor Cloud Agents API to launch the agent on a schedule. No manual UI setup.

1. **Get API key:** [Cursor Dashboard](https://cursor.com/settings) → Integrations → Cloud Agents API
2. **Add secret:** Repo → Settings → Secrets and variables → Actions → New repository secret
   - Name: `CURSOR_AGENTS_API_KEY`
   - Value: your API key
3. **Schedule:** Workflow runs at 7:00 AM UTC daily (`.github/workflows/tldr-reader-daily.yml`). To match local time, adjust the cron (e.g. 7 AM EST = `0 12 * * *`).
4. **Manual run:** Actions tab → TLDR Reader Daily → Run workflow

**Note:** API-launched agents run in Cursor's cloud with repo access. Tool availability (web fetch, Slack, etc.) may differ from UI-configured automations. If the agent cannot fetch tldr.tech, use Option A or C.

### Option C: Cursor Automations UI (manual)

1. **Create** at [cursor.com/automations/new](https://cursor.com/automations/new)
2. **Name:** TLDR Reader - Ultra-Lean Digest
3. **Trigger:** Schedule → Cron `0 7 * * *`. Set timezone to local if supported.
4. **Tools:** Enable Web fetch, Memory, GitHub (create issues), Slack (optional)
5. **Prompt:** Paste contents of `prompt.md`
6. **Memory:** Point to this repo's `memory/` directory

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
