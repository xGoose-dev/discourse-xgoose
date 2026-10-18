import { test, expect } from "@playwright/test";
test.skip(
  process.env.XGOOSE_REAL_API !== "1",
  "Explicit opt-in required for live provider calls.",
);
test("Luna: image understanding, forum research, automatic compaction, dollars, local history and audit", async ({
  page,
  context,
}) => {
  test.setTimeout(240000);
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  const headers = {
    Origin: "http://localhost:3000",
    "X-Requested-With": "XMLHttpRequest",
  };
  const csrf = await (await page.request.get("/session/csrf.json")).json();
  const auth = await page.request.post("/session.json", {
    form: { login: "xgoose_demo", password: process.env.XGOOSE_TEST_PASSWORD },
    headers: { ...headers, "X-CSRF-Token": csrf.csrf },
  });
  expect((await auth.json()).user.username).toBe("xgoose_demo");
  const fixture = await context.newPage();
  await fixture.setContent(
    '<html><body style="margin:0;background:#f4f0ff;font-family:Arial;padding:70px;width:700px"><p style="color:#7851cc;font-size:24px">COMMUNITY RESEARCH</p><h1 style="font-size:52px">Reliable answers</h1><p style="font-size:28px">Read full discussions.<br>Compare sources. Cite exact posts.</p><p style="font-size:32px;font-weight:bold">Verification code: GOOSE-714</p></body></html>',
  );
  const png = await fixture.locator("body").screenshot();
  await fixture.close();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/");
  await page.locator(".xgoose-launcher").click();
  const cfg = await (
    await page.request.get("/xgoose/config", { headers })
  ).json();
  expect(cfg.quota.limit_usd).toBe(2);
  expect(cfg.model).toBe("gpt-6-luna");
  const sessions = [];
  page.on("response", async (r) => {
    if (r.url().endsWith("/xgoose/sessions") && r.request().method() === "POST")
      sessions.push((await r.json()).id);
  });
  async function ask(text) {
    await page.locator("#xgoose-input").fill(text);
    await page.getByRole("button", { name: "Send", exact: true }).click();
    await expect(
      page.getByRole("button", { name: "Stop", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Send", exact: true }),
    ).toBeVisible({ timeout: 150000 });
    await expect(page.locator(".xgoose-error")).toHaveCount(0);
  }
  await ask(
    "Search the forum with the single keyword reliable, then with the single keyword knowledge. Read the matching topics and give three recommendations with citations. Also remember this exact note for our follow-up: PROJECT-MAPLE-927. " +
      "Background for our research: members need reliable answers, full discussion context, dated evidence, and exact citations. ".repeat(
        100,
      ),
  );
  await expect(
    page
      .locator(
        '.xgoose-message[data-role=assistant] a[href*="localhost:3000/t/"]',
      )
      .first(),
  ).toBeVisible();
  await page.locator("#xgoose-images").setInputFiles({
    name: "community-research.png",
    mimeType: "image/png",
    buffer: png,
  });
  await expect(page.locator(".xgoose-attachments img")).toHaveCount(1);
  await ask(
    "Read the verification code in the attached image exactly. Find related forum discussions about its subject, read them, and cite their actual URLs. Also repeat the project note I asked you to remember earlier.",
  );
  const answer = page.locator(".xgoose-message[data-role=assistant]").last();
  await expect(answer).toContainText("GOOSE-714");
  await expect(answer).toContainText("PROJECT-MAPLE-927");
  await expect(page.locator(".xgoose-summary")).toBeVisible();
  await expect(page.locator(".xgoose-message-images img")).toHaveCount(1);
  const transcript = await (
    await page.request.get(`/admin/plugins/xgoose/${sessions[0]}.json`)
  ).json();
  expect(transcript.complete).toBe(true);
  expect(
    transcript.client_reported_events.some((e) => e.kind === "compaction"),
  ).toBe(true);
  expect(
    transcript.requests.every(
      (r) => r.status === "completed" && r.charged_microusd > 0,
    ),
  ).toBe(true);
  expect(JSON.stringify(transcript)).toContain("sha256=");
  expect(JSON.stringify(transcript)).not.toContain("data:image/");
  await page.screenshot({
    path: "docs/screenshots/desktop.png",
    fullPage: true,
  });
  const cost = await page.locator(".xgoose-context").innerText();
  await page.getByRole("button", { name: "Close panel", exact: true }).click();
  await page.locator(".xgoose-launcher").click();
  await expect(page.locator(".xgoose-message")).toHaveCount(0);
  await page.getByRole("button", { name: "Chat history", exact: true }).click();
  await page
    .locator(".xgoose-history-row button")
    .filter({ hasText: "Search the forum with" })
    .click();
  await expect(page.locator(".xgoose-message-images img")).toHaveCount(1);
  await expect(page.locator(".xgoose-thread")).toContainText("GOOSE-714");
  expect(await page.locator(".xgoose-context").innerText()).toBe(cost);
  await page.reload();
  await page.locator(".xgoose-launcher").click();
  await expect(page.locator(".xgoose-message")).toHaveCount(0);
  await page.getByRole("button", { name: "Chat history", exact: true }).click();
  await expect(page.locator(".xgoose-history-row")).toHaveCount(1);
  await page.screenshot({
    path: "docs/screenshots/history.png",
    fullPage: true,
  });
  // Account keys are used for both metadata and full image-bearing transcripts.
  const owners = await page.evaluate(
    () =>
      new Promise((resolve, reject) => {
        const r = indexedDB.open("xgoose-local-history-v1", 1);
        r.onsuccess = () => {
          const db = r.result;
          const tx = db.transaction("entries");
          const q = tx.objectStore("entries").getAll();
          q.onsuccess = () =>
            resolve(q.result.map((x) => ({ owner: x.owner, id: x.id })));
          tx.oncomplete = () => db.close();
        };
        r.onerror = reject;
      }),
  );
  expect(owners).toHaveLength(1);
  expect(owners[0].owner).toContain(":1");
  const admin = await context.newPage();
  await admin.goto("/admin/plugins/xgoose/logs");
  await expect(admin.locator("h1")).toHaveText("xGoose audit logs");
  await admin.goto(`/admin/plugins/xgoose/${sessions[0]}`);
  await expect(admin.locator("body")).toContainText("Transcript complete");
  await expect(admin.locator("body")).toContainText("$");
  await admin.screenshot({
    path: "docs/screenshots/admin-transcript.png",
    fullPage: true,
  });
  if (process.env.XGOOSE_TEST_MEMBER_PASSWORD) {
    const logoutCsrf = await (
      await page.request.get("/session/csrf.json")
    ).json();
    await page.request.delete("/session/xgoose_demo", {
      headers: { ...headers, "X-CSRF-Token": logoutCsrf.csrf },
    });
    const memberCsrf = await (
      await page.request.get("/session/csrf.json")
    ).json();
    const member = await page.request.post("/session.json", {
      form: {
        login: "xgoose_member",
        password: process.env.XGOOSE_TEST_MEMBER_PASSWORD,
      },
      headers: { ...headers, "X-CSRF-Token": memberCsrf.csrf },
    });
    expect((await member.json()).user.username).toBe("xgoose_member");
    await page.reload();
    await page.locator(".xgoose-launcher").click();
    await page
      .getByRole("button", { name: "Chat history", exact: true })
      .click();
    await expect(page.locator(".xgoose-history-row")).toHaveCount(0);
    expect(
      (
        await page.request.get(`/admin/plugins/xgoose/${sessions[0]}.json`)
      ).status(),
    ).not.toBe(200);
  }
  const total =
    transcript.requests.reduce((n, r) => n + r.charged_microusd, 0) / 1e6;
  console.log(
    JSON.stringify({
      model: cfg.model,
      requests: transcript.requests.length,
      total_usd: total,
      image_verified: true,
      auto_summary: true,
      session: sessions[0],
    }),
  );
  expect(errors).toEqual([]);
});
