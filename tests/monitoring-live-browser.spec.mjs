import { test, expect } from "@playwright/test";
const baseURL = process.env.XGOOSE_TEST_BASE_URL || "http://localhost:3000";
const root = "/admin/plugins/discourse-xgoose";
test.skip(
  process.env.XGOOSE_REAL_API !== "1" ||
    !process.env.XGOOSE_TEST_MEMBER_PASSWORD,
  "Explicit live-provider opt-in and isolated fixture required.",
);
async function signIn(context, login, password) {
  const page = await context.newPage();
  const csrf = await (await page.request.get("/session/csrf.json")).json();
  const headers = {
    Origin: baseURL,
    "X-CSRF-Token": csrf.csrf,
    "X-Requested-With": "XMLHttpRequest",
  };
  const response = await page.request.post("/session.json", {
    form: { login, password },
    headers,
  });
  expect((await response.json()).user.username).toBe(login);
  const updated = await (await page.request.get("/session/csrf.json")).json();
  return { page, headers: { ...headers, "X-CSRF-Token": updated.csrf } };
}
test("live Luna budget denial, administrator extension, subsequent generation and monitoring", async ({
  browser,
}) => {
  const adminContext = await browser.newContext();
  const memberContext = await browser.newContext();
  const admin = await signIn(
    adminContext,
    "xgoose_demo",
    process.env.XGOOSE_TEST_PASSWORD,
  );
  const member = await signIn(
    memberContext,
    "xgoose_member",
    process.env.XGOOSE_TEST_MEMBER_PASSWORD,
  );
  const found = await (
    await admin.page.request.get(`${root}/users.json?search=xgoose_member`, {
      headers: admin.headers,
    })
  ).json();
  const userId = found.users.find((u) => u.username === "xgoose_member").id;
  const before = await (
    await admin.page.request.get(`${root}/users/${userId}.json`, {
      headers: admin.headers,
    })
  ).json();
  const change = async (kind, amount) => {
    const response = await admin.page.request.put(
      `${root}/users/${userId}/budget.json`,
      {
        data: {
          kind,
          amount_usd: amount,
          operation_id: crypto.randomUUID(),
          reason: "Synthetic live Luna monitoring verification",
        },
        headers: admin.headers,
      },
    );
    expect(response.status()).toBe(200);
    return (await response.json()).quota;
  };
  let sessionId;
  try {
    await change("daily", 0);
    await member.page.goto("/");
    await member.page.locator(".xgoose-launcher").click();
    await member.page
      .locator("#xgoose-input")
      .fill("Reply with exactly MONITORING-OK. Do not call tools.");
    const created = member.page.waitForResponse(
      (r) =>
        r.url().endsWith("/xgoose/sessions") && r.request().method() === "POST",
    );
    await member.page
      .getByRole("button", { name: "Send", exact: true })
      .click();
    sessionId = (await (await created).json()).id;
    await expect(member.page.locator(".xgoose-error")).toBeVisible();
    const quota = await change(
      "bonus",
      Math.max(before.quota.bonus_usd, before.quota.used_usd + 0.1).toFixed(6),
    );
    expect(quota.remaining_usd).toBeGreaterThan(0);
    await member.page
      .locator("#xgoose-input")
      .fill("Reply with exactly MONITORING-OK. Do not call tools.");
    await member.page
      .getByRole("button", { name: "Send", exact: true })
      .click();
    await expect(
      member.page.getByRole("button", { name: "Stop", exact: true }),
    ).toBeVisible();
    await expect(
      member.page.getByRole("button", { name: "Send", exact: true }),
    ).toBeVisible({ timeout: 90000 });
    await expect(member.page.locator(".xgoose-error")).toHaveCount(0);
    await expect(
      member.page.locator(".xgoose-message[data-role=assistant]").last(),
    ).toContainText("MONITORING-OK");
    const transcript = await (
      await admin.page.request.get(`${root}/sessions/${sessionId}.json`, {
        headers: admin.headers,
      })
    ).json();
    expect(transcript.requests).toHaveLength(1);
    expect(transcript.requests[0].purpose).toBe("generation");
    expect(transcript.requests[0].first_token_ms).toBeGreaterThanOrEqual(0);
    expect(transcript.requests[0].upstream_status).toBe(200);
    const after = await (
      await admin.page.request.get(`${root}/users/${userId}.json`, {
        headers: admin.headers,
      })
    ).json();
    expect(after.report.summary.calls).toBe(before.report.summary.calls + 1);
    expect(after.report.summary.cost).toBe(
      before.report.summary.cost + transcript.requests[0].charged_microusd,
    );
    expect(after.rejections.some((r) => r.reason === "quota_exceeded")).toBe(
      true,
    );
    await admin.page.goto(`${root}/users/${userId}`);
    await expect(admin.page.locator(".xgoose-admin")).toContainText(
      "Synthetic live Luna monitoring verification",
    );
    await expect(admin.page.locator(".xgoose-admin canvas")).toHaveCount(4);
    console.log(
      JSON.stringify({
        sessionId,
        charged_microusd: transcript.requests[0].charged_microusd,
        first_token_ms: transcript.requests[0].first_token_ms,
        model: transcript.requests[0].model,
        complete: transcript.complete,
      }),
    );
  } finally {
    // Restore the daily policy first; spent bonus is covered by the restored base.
    await change("daily", before.quota.personal_limit_usd);
    await change("bonus", before.quota.bonus_usd);
    await memberContext.close();
    await adminContext.close();
  }
});
