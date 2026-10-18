import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*browser.spec.mjs",
  timeout: 120000,
  workers: 1,
  use: {
    baseURL: process.env.XGOOSE_TEST_BASE_URL || "http://localhost:3000",
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
});
