# TLDR Reader — Playwright UI Setup

Automates creation of the Cursor automation via the web UI.

## Prerequisites

- Node.js 18+
- Cursor account (you'll log in on first run)

## Run

```bash
cd .cursor/automations/tldr-reader-ultra-lean/playwright
npm install
npm run setup   # installs Chromium + runs script
# or
npm run run     # runs script only (after first setup)
```

## First run

1. Script opens a browser and navigates to cursor.com/automations/new
2. If you see a login screen, log in manually
3. Press Enter in the terminal when logged in
4. Script saves auth state to `.auth-state.json` (gitignored)
5. Script attempts to fill: name, prompt, cron, tools, repo
6. Review the form and click Create/Save manually if needed
7. Press Enter to close

## Subsequent runs

Auth state is reused. Script fills the form; you may need to click Create/Save.

## Environment

- `GITHUB_REPO_URL` — Override repo URL (default: this project's GitHub URL)

## Notes

- Cursor's UI may change; selectors might need updates
- Run in headed mode (visible browser) so you can correct any missed fields
