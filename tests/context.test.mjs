import test from "node:test";
import assert from "node:assert/strict";
import { estimateContext, summaryInput } from "../frontend/context.js";
import { createResearchAgent } from "../frontend/agent.js";

test("image estimates count image allowance rather than base64 length; summary omits image pixels", () => {
  const messages = [
    {
      role: "user",
      content: [
        { type: "text", text: "Find this" },
        { type: "image", data: "A".repeat(500000), mimeType: "image/png" },
      ],
    },
  ];
  assert.ok(estimateContext(messages) > 8192);
  assert.ok(estimateContext(messages) < 9000);
  assert.ok(summaryInput(messages).includes("attached image"));
  assert.ok(!summaryInput(messages).includes("A".repeat(100)));
});
test("Pi automatically summarizes long context, preserves the latest image and never duplicates model replies", async () => {
  const originalFetch = globalThis.fetch;
  const requests = [],
    summaries = [];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    requests.push(body);
    const text = body.tools?.length
      ? "Verified answer [source](http://localhost/t/7/1)"
      : "Keep PROJECT-MAPLE-927 and http://localhost/t/7/1.";
    const payload = [
      {
        id: "test",
        object: "chat.completion.chunk",
        created: 1,
        model: "test",
        choices: [
          {
            index: 0,
            delta: { role: "assistant", content: text },
            finish_reason: null,
          },
        ],
      },
      {
        id: "test",
        choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
        usage: { prompt_tokens: 100, completion_tokens: 10, total_tokens: 110 },
      },
    ];
    return new Response(
      payload.map((p) => `data: ${JSON.stringify(p)}\n\n`).join("") +
        "data: [DONE]\n\n",
      { headers: { "Content-Type": "text/event-stream" } },
    );
  };
  try {
    const agent = createResearchAgent({
      config: {
        model: "test",
        context_tokens: 32768,
        max_output_tokens: 2048,
        max_turn_calls: 8,
        system_prompt: "Research",
      },
      sessionId: 1,
      endpoint: "http://localhost/xgoose/sessions/1",
      csrfToken: () => "",
      fetchJson: async () => ({}),
      onEvent: () => {},
      onCompaction: (e) => summaries.push(e),
      initialMessages: [
        {
          role: "user",
          content: "Earlier background " + "x".repeat(20000),
          timestamp: 1,
        },
        {
          role: "assistant",
          content: [{ type: "text", text: "PROJECT-MAPLE-927" }],
          timestamp: 2,
          api: "openai-completions",
          provider: "xgoose",
          model: "test",
          stopReason: "stop",
          usage: {
            input: 1,
            output: 1,
            totalTokens: 2,
            cost: { input: 0, output: 0, total: 0 },
          },
        },
      ],
    });
    await agent.prompt("What about this picture?", [
      { data: "aGVsbG8=", mimeType: "image/png" },
    ]);
    assert.equal(requests.length, 2);
    assert.ok(
      requests[0].messages.some((m) =>
        JSON.stringify(m).includes("Summarize the following conversation"),
      ),
    );
    assert.ok(
      requests[1].messages.some((m) =>
        JSON.stringify(m).includes("data:image/png;base64,aGVsbG8="),
      ),
    );
    assert.ok(
      requests[1].messages.some((m) =>
        JSON.stringify(m).includes("Keep PROJECT-MAPLE-927"),
      ),
    );
    assert.equal(
      agent.agent.state.messages.filter((m) => m.role === "assistant").length,
      1,
    );
    assert.equal(summaries.filter((e) => !e.running).length, 1);
    assert.ok(
      estimateContext(agent.agent.state.messages) < 10000,
      JSON.stringify(
        agent.agent.state.messages.map((m) => ({
          role: m.role,
          length: JSON.stringify(m).length,
        })),
      ),
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
