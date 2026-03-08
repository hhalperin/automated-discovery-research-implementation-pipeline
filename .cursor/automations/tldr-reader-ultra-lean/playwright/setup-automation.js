#!/usr/bin/env node
/**
 * TLDR Reader — Playwright automation setup
 * Creates the Cursor automation via the UI at cursor.com/automations/new
 *
 * First run: You will be prompted to log in. Auth state is saved for future runs.
 * Run: npm run run  (or: node setup-automation.js)
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const AUTH_STATE_PATH = path.join(__dirname, '.auth-state.json');
const PROMPT_PATH = path.join(__dirname, '..', 'prompt.md');
const AUTOMATION_URL = 'https://cursor.com/automations/new';

const CONFIG = {
  name: 'TLDR Reader - Ultra-Lean Digest',
  cron: '0 7 * * *',
  prompt: fs.readFileSync(PROMPT_PATH, 'utf8'),
};

async function main() {
  const useExistingAuth = fs.existsSync(AUTH_STATE_PATH);
  const browser = await chromium.launch({
    headless: false,
    slowMo: 100,
  });

  const contextOptions = {
    viewport: { width: 1280, height: 900 },
    locale: 'en-US',
  };
  if (useExistingAuth) {
    contextOptions.storageState = AUTH_STATE_PATH;
  }

  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();

  try {
    await page.goto(AUTOMATION_URL, { waitUntil: 'networkidle', timeout: 30000 });
  } catch (e) {
    console.error('Failed to load page. If you see a login screen, log in manually.');
  }

  // Wait for either login redirect or automation form
  await page.waitForTimeout(3000);

  const currentUrl = page.url();
  if (currentUrl.includes('login') || currentUrl.includes('auth') || currentUrl.includes('signin')) {
    console.log('\n>>> Please log in to Cursor in the browser window. Press Enter when done.');
    await new Promise((r) => process.stdin.once('data', r));
  }

  // Save auth state for next run
  await context.storageState({ path: AUTH_STATE_PATH });
  console.log('Auth state saved.');

  // Navigate to automation creation if we were on a different page
  if (!page.url().includes('automations')) {
    await page.goto(AUTOMATION_URL, { waitUntil: 'networkidle', timeout: 30000 });
  }

  await page.waitForTimeout(2000);

  // Step 1: Name the automation
  const nameSelectors = [
    'input[placeholder*="name" i]',
    'input[placeholder*="Name" i]',
    '[data-testid="automation-name"]',
    'input[name="name"]',
    'input[aria-label*="name" i]',
  ];
  for (const sel of nameSelectors) {
    try {
      const el = await page.locator(sel).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.fill(CONFIG.name);
        console.log('Filled automation name.');
        break;
      }
    } catch (_) {}
  }

  // Step 2: Prompt
  const promptSelectors = [
    'textarea[placeholder*="prompt" i]',
    'textarea[placeholder*="instruction" i]',
    'textarea[placeholder*="task" i]',
    '[data-testid="automation-prompt"]',
    'textarea[name="prompt"]',
    'div[contenteditable="true"]',
    'textarea',
  ];
  for (const sel of promptSelectors) {
    try {
      const el = await page.locator(sel).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.fill('');
        await el.fill(CONFIG.prompt);
        console.log('Filled prompt.');
        break;
      }
    } catch (_) {}
  }

  // Step 3: Trigger — Schedule / Cron
  const scheduleSelectors = [
    'button:has-text("Schedule")',
    'button:has-text("schedule")',
    '[data-testid="trigger-schedule"]',
    'text=Schedule',
    'text=Cron',
  ];
  for (const sel of scheduleSelectors) {
    try {
      const el = page.locator(sel).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.click();
        await page.waitForTimeout(500);
        break;
      }
    } catch (_) {}
  }

  const cronSelectors = [
    'input[placeholder*="cron" i]',
    'input[placeholder*="0 * * * *" i]',
    'input[name="cron"]',
    '[data-testid="cron-input"]',
  ];
  for (const sel of cronSelectors) {
    try {
      const el = await page.locator(sel).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.fill(CONFIG.cron);
        console.log('Filled cron:', CONFIG.cron);
        break;
      }
    } catch (_) {}
  }

  // Step 4: Enable tools — Web fetch, Memory, GitHub, Slack (click tool cards/toggles)
  const toolLabels = ['Web', 'Memory', 'GitHub', 'Slack'];
  for (const label of toolLabels) {
    try {
      const el = page.locator(`text=${label}`).or(page.locator(`[aria-label*="${label}" i]`)).first();
      if (await el.isVisible({ timeout: 300 })) {
        await el.click();
        await page.waitForTimeout(200);
      }
    } catch (_) {}
  }

  // Step 5: Repository — if required
  const repoUrl = process.env.GITHUB_REPO_URL || 'https://github.com/hhalperin/automated-discovery-research-implementation-pipeline';
  const repoSelectors = [
    'input[placeholder*="repository" i]',
    'input[placeholder*="github" i]',
    'input[name="repository"]',
  ];
  for (const sel of repoSelectors) {
    try {
      const el = await page.locator(sel).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.fill(repoUrl);
        console.log('Filled repository.');
        break;
      }
    } catch (_) {}
  }

  console.log('\n>>> Review the form in the browser. Click Create/Save manually if the script did not find all fields.');
  console.log('>>> Press Enter when done to close.');
  await new Promise((r) => process.stdin.once('data', r));

  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
