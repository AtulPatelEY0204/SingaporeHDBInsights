import { defineConfig, devices } from '@playwright/test';

// UI_BASE_URL is the app root, e.g. https://test.hdb.example.com/SingaporeHDBInsight/
export default defineConfig({
  testDir: '.',
  timeout: 60_000,
  expect: { timeout: 20_000 },
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['junit', { outputFile: 'junit-ui.xml' }], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.UI_BASE_URL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'phone', use: { ...devices['Pixel 7'] } },
  ],
});
