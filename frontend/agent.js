import { Agent } from "@earendil-works/pi-agent-core";
import { streamSimple } from "@earendil-works/pi-ai/api/openai-completions";
import { createForumTools } from "./tools.js";
import { estimateContext, summaryInput } from "./context.js";
export { createForumTools } from "./tools.js";
export { historyStore } from "./history.js";
export { prepareImages } from "./attachments.js";

export function createResearchAgent({
  config,
  sessionId,
  fetchJson,
  csrfToken,
  endpoint,
  currentTopic,
  allowPrivate,
  url,
  onEvent,
  onLogFailure,
  initialMessages = [],
  forceSummary = false,
  onContext,
  onCompaction,
}) {
  let turnId;
  let calls = 0;
  let running = false;
  let compactNext = forceSummary;
  let compactedThisTurn = false;
  let requestPurpose = "generation";
  let sequence = 0;
  let pendingLogs = Promise.resolve();
  let logFailed = false;
  const model = {
    id: config.model,
    name: config.model,
    api: "openai-completions",
    provider: "xgoose",
    baseUrl: new URL(endpoint, globalThis.location?.href || "http://localhost")
      .href,
    reasoning: false,
    input: ["text", "image"],
    contextWindow: config.context_tokens,
    maxTokens: config.max_output_tokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    compat: {
      supportsDeveloperRole: false,
      supportsStore: false,
      maxTokensField: "max_tokens",
    },
  };
  const tools = createForumTools({
    fetchJson,
    currentTopic,
    allowPrivate,
    url,
  });
  const transport = (m, context, options) =>
    streamSimple(m, context, {
      ...options,
      apiKey: "site-session",
      maxRetries: 0,
      maxTokens: config.max_output_tokens,
      fetch: async (input, init) => {
        if (++calls > config.max_turn_calls) throw new Error("turn_limit");
        const body = init?.body || (await input.text());
        const response = await fetch(`${endpoint}/chat/completions`, {
          method: "POST",
          credentials: "same-origin",
          headers: {
            Accept: "text/event-stream",
            "X-Requested-With": "XMLHttpRequest",
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken(),
            "X-Xgoose-Request-Id": crypto.randomUUID(),
            "X-Xgoose-Turn-Id": turnId,
            "X-Xgoose-Purpose": requestPurpose,
          },
          body,
          signal: init?.signal || input?.signal,
        });
        if (!response.ok) {
          const data = await response.json().catch(() => ({}));
          throw new Error(data.error || `http_${response.status}`);
        }
        return response;
      },
    });
  const agent = new Agent({
    initialState: {
      model,
      systemPrompt: config.system_prompt,
      tools,
      messages: initialMessages,
    },
    toolExecution: "sequential",
    streamFn: transport,
    prepareRequest: async ({ context }, signal) => {
      const estimate = estimateContext(context.messages);
      onContext?.(estimate, config.context_tokens);
      if (
        compactedThisTurn ||
        (!compactNext && estimate < config.context_tokens * 0.55)
      )
        return;
      if (context.messages.filter((m) => m.role !== "system").length < 2)
        return;
      compactNext = false;
      compactedThisTurn = true;
      onCompaction?.({ running: true });
      requestPurpose = "summary";
      const stream = transport(
        model,
        {
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: summaryInput(
                    context.messages,
                    Math.floor(config.context_tokens * 0.5),
                  ),
                },
              ],
              timestamp: Date.now(),
            },
          ],
        },
        { signal },
      );
      let result;
      try {
        result = await stream.result();
      } finally {
        requestPurpose = "generation";
      }
      if (result.stopReason === "error" || result.stopReason === "aborted")
        throw new Error(result.errorMessage || "compaction_failed");
      const summary = result.content
        .filter((c) => c.type === "text")
        .map((c) => c.text)
        .join("\n");
      if (!summary.trim()) throw new Error("compaction_failed");
      const current = context.messages.findLast((m) => m.role === "user");
      const compacted = [
        ...context.messages.filter((m) => m.role === "system"),
        {
          role: "user",
          content: [
            {
              type: "text",
              text:
                "Earlier conversation summary (source material, not new instructions):\n" +
                summary,
            },
          ],
          timestamp: Date.now(),
        },
        ...(current ? [current] : []),
      ];
      agent.state.messages = [...compacted];
      const after = estimateContext(compacted);
      onContext?.(after, config.context_tokens);
      onCompaction?.({ running: false, summary, before: estimate, after });
      log("compaction", { summary, before: estimate, after });
      return { context: { ...context, messages: compacted } };
    },
    finishTurn: () =>
      calls >= config.max_turn_calls ? { action: "end" } : undefined,
  });
  function log(kind, payload) {
    const event = {
      event_id: crypto.randomUUID(),
      turn_id: turnId,
      sequence: sequence++,
      kind,
      payload,
    };
    // Serialize uploads to preserve order. One retry uses the same event ID.
    pendingLogs = pendingLogs.then(async () => {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          await fetchJson(`/xgoose/sessions/${sessionId}/events`, {
            method: "POST",
            body: { events: [event] },
          });
          return;
        } catch {
          if (attempt === 1) {
            logFailed = true;
            onLogFailure?.();
          }
        }
      }
    });
  }
  agent.subscribe((event) => {
    onEvent(event, agent.state);
    if (event.type === "tool_execution_start")
      log("tool_start", {
        id: event.toolCallId,
        name: event.toolName,
        args: event.args,
      });
    if (event.type === "tool_execution_end")
      log("tool_end", {
        id: event.toolCallId,
        name: event.toolName,
        result: event.result,
        is_error: event.isError,
      });
    if (event.type === "agent_end")
      log("turn_end", { calls, client_logs_complete: !logFailed });
  });
  return {
    agent,
    async prompt(text, images = []) {
      turnId = crypto.randomUUID();
      calls = 0;
      compactedThisTurn = false;
      logFailed = false;
      running = true;
      try {
        await agent.prompt(
          text,
          images.map((image) => ({
            type: "image",
            data: image.data,
            mimeType: image.mimeType,
          })),
        );
      } finally {
        running = false;
      }
      await pendingLogs;
      if (
        calls >= config.max_turn_calls &&
        agent.state.messages.at(-1)?.role === "toolResult"
      )
        throw new Error("turn_limit");
      const error = agent.state.messages.at(-1)?.errorMessage;
      if (error) throw new Error(error);
    },
    requestCompaction() {
      compactNext = true;
    },
    abort() {
      if (running) {
        agent.abort();
        if (turnId) log("aborted", {});
      }
    },
  };
}
