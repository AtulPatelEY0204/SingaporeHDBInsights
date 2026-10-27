import { test, expect, Page } from '@playwright/test';

// Smoke tests for the public PriceCheck screen and the admin access rule.
// Selectors use the app's own hdb-* classes and visible text so they survive
// OutSystems re-renders. Assumes the environment has an active snapshot.

async function openPriceCheck(page: Page) {
  await page.goto('./');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('What did flats like yours actually sell for?');
  // Freshness pill in the hero shows either the data date or an explicit stale/no-data warning, never nothing.
  await expect(page.locator('.hdb-pill').first()).toContainText(/Data as of|Heads up|No data has been loaded/);
}

async function choose(page: Page, label: string, option: string) {
  await page.locator('.hdb-field').filter({ hasText: label }).locator('select').selectOption({ label: option });
}

test('PriceCheck loads with summary, chart and attribution', async ({ page }) => {
  await openPriceCheck(page);
  await expect(page.locator('.hdb-kpi')).toHaveCount(4);
  await expect(page.getByText('Monthly median resale price, last 5 years')).toBeVisible();
  await expect(page.locator('.hdb-footer')).toContainText('Singapore Open Data Licence');
});

test('filtering by town and flat type returns priced transactions', async ({ page }) => {
  await openPriceCheck(page);
  await choose(page, 'Town', 'TAMPINES');
  await choose(page, 'Flat type', '4 ROOM');
  await page.getByRole('button', { name: 'Check prices' }).click();

  const median = page.locator('.hdb-kpi__value').first();
  await expect(median).toHaveText(/^S\$[\d,]+$/);
  const rows = page.locator('.hdb-table .hdb-row:not(.hdb-row--head)');
  await expect(rows.first()).toBeVisible();
  await expect(rows.first()).toContainText('TAMPINES');
  await expect(page.getByText(/newest first/)).toBeVisible();
});

test('pagination moves to the next page', async ({ page }) => {
  await openPriceCheck(page);
  await choose(page, 'Town', 'TAMPINES');
  await page.getByRole('button', { name: 'Check prices' }).click();
  const summary = page.getByText(/^Showing 1–20 of/);
  await expect(summary).toBeVisible();
  await page.locator('.pagination').getByRole('button', { name: /next/i }).click();
  await expect(page.getByText(/^Showing 21–40 of/)).toBeVisible();
});

test('period chips re-run the search for the chosen window', async ({ page }) => {
  await openPriceCheck(page);
  const threeYears = page.getByRole('link', { name: 'Last 3 years' });
  await threeYears.click();
  await expect(threeYears).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByText('In the last 36 months of data')).toBeVisible();
});

test('more filters reveals the storey, size and lease fields', async ({ page }) => {
  await openPriceCheck(page);
  const storey = page.locator('.hdb-field').filter({ hasText: 'Min. storey' });
  await expect(storey).toBeHidden();
  await page.getByText('More filters').click();
  await expect(storey).toBeVisible();
});

test('no horizontal page scroll on any viewport (tables scroll inside their card)', async ({ page }) => {
  await openPriceCheck(page);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(1);
});

// SyncAdmin lives in its own module (HDBResale_Admin), a sibling of the public
// app's path. From outside admin_allowed_cidrs the WAF answers 403; from inside,
// the screen's HDBAdmin role sends anonymous visitors to Login. Either is a pass.
test('SyncAdmin is not reachable anonymously', async ({ page, baseURL }) => {
  const adminUrl = process.env.ADMIN_BASE_URL ?? new URL('../HDBResale_Admin/', baseURL).toString();
  const response = await page.goto(new URL('SyncAdmin', adminUrl).toString());
  if (response?.status() === 403) return;
  await expect(page).toHaveURL(/Login/i);
  await expect(page.getByText('Recent sync runs')).toHaveCount(0);
});

test('public app no longer exposes SyncAdmin', async ({ page }) => {
  await page.goto('./SyncAdmin');
  await expect(page.getByText('Recent sync runs')).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Sync admin' })).toHaveCount(0);
});
