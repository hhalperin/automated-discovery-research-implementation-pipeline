# TLDR Reader — Ultra-Lean Digest

A **Cursor Automation** that runs on a schedule, scans TLDR Tech for high-leverage ideas matching your repos, and creates GitHub issues only when justified.

**Primary path:** Cursor Automations (UI) or Playwright-assisted setup. **Fallback only:** GitHub Actions calling the Cloud Agents API (different tool surface—see caveats).

## Required configuration

Set these before first production run. Paths are relative to the repo root unless noted.

| Item | Where / value | Notes |
|------|----------------|--------|
| Automation name | `automation-spec.yaml` → `name` | e.g. TLDR Reader - Ultra-Lean Digest |
| Prompt (production) | `automation-spec.yaml` → `prompt_file` | Paste or sync `prompt.md` into the automation |
| Prompt (probe) | `automation-spec.yaml` → `prompt_probe_file` | Use `prompt.probe.md` for capability checks |
| Repository | `automation-spec.yaml` → `repo.url` | e.g. `https://github.com/org/repo` |
| Branch / ref | `automation-spec.yaml` → `repo.ref` | Pin `main` or a release branch for production |
| Schedule | `automation-spec.yaml` → `trigger` | Cron `0 7 * * *`, timezone local or UTC |
| Memory directory | Cursor UI: Memory | Point to `memory/` under this folder |
| Tools | Cursor UI | Enable Web fetch, Memory, GitHub (issues), Slack optional |
| GitHub Actions secret | Repo → Secrets | `CURSOR_AGENTS_API_KEY` if using fallback workflow |

## Setup options

Cursor does not expose an API to create automations (UI only). Three ways to run this:

### Option A: Cursor Automations UI (recommended primary)

1. **Create** at [cursor.com/automations/new](https://cursor.com/automations/new)
2. **Name:** match `automation-spec.yaml` → `name`
3. **Trigger:** Schedule → Cron `0 7 * * *`. Set timezone to local if supported.
4. **Tools:** Enable Web fetch, Memory, GitHub (create issues), Slack (optional)
5. **Prompt:** Paste contents of `prompt.md` (production)
6. **Memory:** Point to this directory’s `memory/` folder

**Schedule:** Leave the automation **paused / not scheduled** until [Production gate](#production-gate) is satisfied (probe pass + one manual production run).

### Option B: Playwright UI automation (first-time setup helper)

Uses Playwright to fill the automation form at cursor.com/automations/new.

```bash
cd .cursor/automations/tldr-reader-ultra-lean/playwright
npm install && npm run setup
```

First run: log in when prompted, then the script fills name, prompt, cron, tools. Review and click Create. See `playwright/README.md` for details.

### Option C: GitHub Actions + Cloud Agents API (fallback only)

Uses the Cursor Cloud Agents API to launch the agent on a schedule. No manual UI setup; tool availability may differ from UI automations.

1. **Get API key:** [Cursor Dashboard](https://cursor.com/settings) → Integrations → Cloud Agents API
2. **Add secret:** Repo → Settings → Secrets and variables → Actions → New repository secret
   - Name: `CURSOR_AGENTS_API_KEY` (or `CURSOR_API_KEY` / `CURSOR_CLOUD_AGENTS_API_KEY` — the workflow accepts any of these)
   - Value: your API key
   - **Important:** Storing the key only in Cursor IDE user settings does **not** supply it to GitHub Actions. You must add it as an Actions secret on this repository (or use an organization secret with access to the repo).
3. **Workflow / schedule:** `.github/workflows/tldr-reader-daily.yml` runs on cron `0 7 * * *` (UTC). To match local wall clock, adjust the cron in that file (e.g. 7 AM EST = `0 12 * * *`).
4. **Manual run:** Actions tab → TLDR Reader Daily → Run workflow

**Note:** API-launched agents run in Cursor's cloud with repo access. Tool availability (web fetch, Slack, etc.) may differ from UI-configured automations. If the agent cannot fetch tldr.tech, prefer Option A or B.

## Known caveats

- **No automation API:** Cursor Automations must be created or updated in the UI (or via Playwright); there is no public API to register them.
- **Cloud vs UI tools:** Cloud/API agents may not expose the same tools as a hand-configured automation; run [Probe](#production-gate) before relying on schedule.
- **Cron and timezone:** GitHub Actions uses UTC unless you change the workflow cron; align `trigger.timezone` in `automation-spec.yaml` with how you think about “morning” runs.
- **Secrets:** Never commit API keys; use repository secrets for Actions.

## Scheduler reset procedure

Use when changing cron, timezone, or after disabling a broken schedule.

1. **Pause or delete** the existing automation schedule in the Cursor UI (or disable the GitHub Actions workflow).
2. **Update** `automation-spec.yaml` (`trigger.cron`, `trigger.timezone`) and this README if the schedule string changed.
3. **Re-validate:** From repo root: `sh scripts/validate-tldr-reader.sh`
4. **Re-run [Production gate](#production-gate)** (probe, then one manual production run) before turning the schedule back on.

## Production gate

Do **not** enable daily scheduling until:

1. **Probe pass:** Run the automation once with `prompt.probe.md` (or paste its contents). Confirm `ready_for_production: true` in the JSON between `BEGIN PROBE REPORT JSON` / `END PROBE REPORT JSON`.
2. **One manual production pass:** Run once with `prompt.md` on a chosen date; confirm a valid JSON block between `BEGIN PRODUCTION FINAL REPORT JSON` / `END PRODUCTION FINAL REPORT JSON` and expected memory updates.

Optional GitHub write check: run probe with operator instruction `PROBE_ALLOW_GITHUB_WRITE=true` only if you accept a single test issue.

## Operator runbook

### Strict run sequence

1. Edit `repo` and `prompt_file` in `automation-spec.yaml` if this fork differs.
2. Run `sh scripts/validate-tldr-reader.sh` from the repository root.
3. Run **probe** (`prompt.probe.md`) once; archive the probe JSON for evidence.
4. Run **production** (`prompt.md`) manually once; archive the production JSON.
5. Only then enable the schedule in Cursor (or enable the Actions workflow if using fallback).

### Verification matrix

| Check | How |
|-------|-----|
| Files present | `sh scripts/validate-tldr-reader.sh` exits 0 |
| Spec vs README | Script ensures cron in spec appears in this README |
| Probe JSON | Output contains valid JSON between probe markers with `ready_for_production` |
| Production JSON | Output contains valid JSON between production markers with `outcome` set |
| Memory | `tldr_archive` / `evaluation_history` updated on success paths (or noted in `blocking_reasons` if degraded) |

### Evidence checklist

- [ ] Validator output: `validate-tldr-reader: OK`
- [ ] Saved probe report JSON (file or log excerpt)
- [ ] Saved production final report JSON
- [ ] Note of date/timezone used for the TLDR URL

### Degraded-mode playbook

If the final report shows `outcome: "degraded_manual_handoff"`:

1. Read `blocking_reasons[]` and any `issue_drafts[]` in the JSON.
2. Fix environment issues (tools, secrets, memory paths, GitHub permissions).
3. Re-run probe; then one manual production run before re-enabling schedule.
4. Manually create GitHub issues from `issue_drafts[]` if drafts are present and still valid.

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

## Scheduling (reference)

- **Cron:** `0 7 * * *`
- **Timezone:** Use local if the platform supports it; otherwise UTC (note offset in the production final report `summary_one_line` or `blocking_reasons`)

**Reminder:** Keep the schedule **off** in docs and UI until [Production gate](#production-gate) is complete.

## Success criteria

A successful run either:

1. Creates 1–3 relevant GitHub issues for free/high-value ideas, or
2. Quietly concludes there was nothing worth acting on (`success_no_hits` in the final JSON).

Zero-action days produce no Slack and no issues—only memory updates and the structured final JSON.

## Failure modes avoided

- Noisy issue spam
- Shallow summaries without action
- Duplicate ideas
- Irrelevant repo mapping
- Expensive model calls on weak candidates
- Re-processing archive duplicates
- Broad research rabbit holes
