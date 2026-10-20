import { test, expect } from "@playwright/test";
const password = process.env.XGOOSE_TEST_PASSWORD;
const baseURL = process.env.XGOOSE_TEST_BASE_URL || "http://localhost:3000";
const root = "/admin/plugins/discourse-xgoose";
test.skip(!password, "Requires the isolated local Discourse fixture.");
async function login(page, name = "xgoose_demo", pass = password) {
  const csrf = await (await page.request.get("/session/csrf.json")).json();
  const response = await page.request.post("/session.json", {
    form: { login: name, password: pass },
    headers: {
      "X-CSRF-Token": csrf.csrf,
      "X-Requested-With": "XMLHttpRequest",
      Origin: baseURL,
    },
  });
  expect((await response.json()).user?.username).toBe(name);
}
test("native admin overview, user budget, logs, and transcript", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await login(page);
  await page.setViewportSize({ width: 1440, height: 1100 });
  await page.goto(`${root}/overview`);
  await expect(page.locator(".xgoose-admin")).toContainText(
    "Charged usage (USD)",
  );
  await expect(page.locator(".xgoose-admin canvas")).toHaveCount(4);
  await expect(page.getByLabel("Period", { exact: true })).toHaveValue("7");
  await expect(page.locator(".xgoose-admin .alert-error")).toHaveCount(0);
  await page.screenshot({
    path: "test-results/admin-overview.png",
    fullPage: true,
  });
  await page.getByRole("link", { name: "User usage", exact: true }).click();
  await expect(page.locator(".xgoose-admin-table")).toContainText(
    "xgoose_demo",
  );
  await page
    .locator(".xgoose-admin-table")
    .getByRole("button", { name: "xgoose_demo", exact: true })
    .click();
  await expect(page.locator(".xgoose-admin")).toContainText(
    "Budget change history",
  );
  await page.getByText("Manage this user’s budget", { exact: true }).click();
  await page
    .getByLabel("Reason", { exact: true })
    .fill("Local administrator UI verification");
  await page.getByLabel("Daily base limit (USD)", { exact: true }).fill("2");
  await page
    .getByRole("button", { name: "Save daily limit", exact: true })
    .click();
  await expect(page.locator(".alert-success")).toContainText("Budget updated");
  await expect(page.locator(".xgoose-admin")).toContainText(
    "Local administrator UI verification",
  );
  await page.getByText("Manage this user’s budget", { exact: true }).click();
  await page
    .getByLabel("Reason", { exact: true })
    .fill("Restore site default after UI verification");
  await page.getByLabel("Daily base limit (USD)", { exact: true }).fill("");
  await page
    .getByRole("button", { name: "Save daily limit", exact: true })
    .click();
  await expect(page.locator(".alert-success")).toContainText("Budget updated");
  await page
    .getByRole("link", { name: "Conversation logs", exact: true })
    .click();
  await expect(
    page.locator(".xgoose-admin-table tbody tr").first(),
  ).toContainText(/xgoose_(demo|member)/);
  await page
    .locator(".xgoose-admin-table")
    .getByRole("button", { name: /^#\d+$/ })
    .first()
    .click();
  await expect(page.locator(".xgoose-admin")).toContainText(
    "Original model requests",
  );
  await expect(page.locator(".xgoose-admin-turn")).not.toHaveCount(0);
  await expect(page.locator(".xgoose-admin .alert-error")).toHaveCount(0);
  await page.screenshot({
    path: "test-results/admin-transcript.png",
    fullPage: true,
  });
  expect(errors).toEqual([]);
});
test("member cannot access monitoring reports or change budgets", async ({
  page,
}) => {
  test.skip(!process.env.XGOOSE_TEST_MEMBER_PASSWORD);
  await login(page, "xgoose_member", process.env.XGOOSE_TEST_MEMBER_PASSWORD);
  for (const path of [
    "overview",
    "users",
    "sessions",
    "rejections",
    "users/1",
  ]) {
    const response = await page.request.get(`${root}/${path}.json`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    });
    expect(response.status()).not.toBe(200);
  }
});
test("Chinese mobile monitoring uses the native admin layout", async ({
  page,
}) => {
  await login(page);
  const csrf = await (await page.request.get("/session/csrf.json")).json();
  const headers = {
    "X-CSRF-Token": csrf.csrf,
    "X-Requested-With": "XMLHttpRequest",
    Origin: baseURL,
  };
  try {
    expect(
      (
        await page.request.put("/u/xgoose_demo.json", {
          form: { locale: "zh_CN" },
          headers,
        })
      ).status(),
    ).toBe(200);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.goto(`${root}/overview`);
    await expect(page.locator(".xgoose-admin")).toContainText(
      "计费用量（美元）",
    );
    await expect(page.locator(".xgoose-admin canvas")).toHaveCount(4);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBeLessThanOrEqual(390);
    await page.screenshot({
      path: "test-results/admin-mobile-zh.png",
      fullPage: true,
    });
  } finally {
    expect(
      (
        await page.request.put("/u/xgoose_demo.json", {
          form: { locale: "en" },
          headers,
        })
      ).status(),
    ).toBe(200);
  }
});
