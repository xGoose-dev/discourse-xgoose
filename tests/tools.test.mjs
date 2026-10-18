import test from "node:test";
import assert from "node:assert/strict";
import { DOMParser } from "linkedom";
import { createForumTools, plainText } from "../frontend/tools.js";
globalThis.DOMParser = DOMParser;
function tools(fetchJson, allowPrivate = () => false) {
  return Object.fromEntries(
    createForumTools({ fetchJson, currentTopic: () => 42, allowPrivate }).map(
      (t) => [t.name, t],
    ),
  );
}
const run = (tool, args = {}) =>
  tool
    .execute("test", args, new AbortController().signal)
    .then((r) => r.details);
test("forum search rejects injected private scope and paginates", async () => {
  let requested;
  const t = tools(async (path) => {
    requested = path;
    return {
      topics: [{ id: 42, title: "Example" }],
      posts: [{ id: 7, topic_id: 42, post_number: 2, blurb: "Snippet" }],
      grouped_search_result: { more_full_page_results: true },
    };
  });
  await assert.rejects(
    run(t.search_forum, { query: "secret in:personal" }),
    /invalid_search_scope/,
  );
  const result = await run(t.search_forum, {
    query: "hello",
    page: 2,
    category: 3,
  });
  assert.match(requested, /page=2/);
  assert.match(requested, /category/);
  assert.equal(result.next_page, 3);
  assert.equal(result.posts[0].url, "/t/42/2");
});
test("private searches require an explicit user opt-in", async () => {
  const t = tools(async () => ({}));
  await assert.rejects(
    run(t.search_private_messages, { query: "secret" }),
    /private_messages_disabled/,
  );
  const reads = tools(async () => ({
    id: 42,
    archetype: "private_message",
    post_stream: { posts: [] },
  }));
  await assert.rejects(
    run(reads.read_topic, { topic_id: 42 }),
    /private_messages_disabled/,
  );
});
test("topic reading exposes truncation and subsequent pages", async () => {
  const t = tools(async () => ({
    id: 42,
    title: "Long topic",
    posts_count: 30,
    highest_post_number: 30,
    post_stream: {
      posts: Array.from({ length: 20 }, (_, n) => ({
        id: n + 1,
        post_number: n + 1,
        cooked: `<html><body><p>${"x".repeat(7000)}</p></body></html>`,
      })),
    },
  }));
  const result = await run(t.read_topic, { topic_id: 42 });
  assert.equal(result.posts.length, 10);
  assert.equal(result.next_post_number, 11);
  assert.equal(result.posts[0].truncated, true);
  assert.equal(result.posts[0].next_offset, 800);
  assert.equal(result.complete, false);
});
test("tools propagate abort signals and forum 429 failures", async () => {
  const controller = new AbortController();
  let signal;
  const t = tools(async (_path, init) => {
    signal = init.signal;
    throw new Error("rate_limited");
  });
  await assert.rejects(
    t.latest_topics.execute("id", {}, controller.signal),
    /rate_limited/,
  );
  assert.equal(signal, controller.signal);
});
test("all tools are read only, with no JS execution or URL fetch escape hatch", () => {
  const names = Object.keys(tools(async () => ({})));
  assert.deepEqual(names, [
    "search_forum",
    "search_private_messages",
    "read_topic",
    "read_posts",
    "categories",
    "latest_topics",
    "current_topic",
  ]);
});
test("source HTML is converted to text without executable content", () => {
  assert.equal(
    plainText(
      "<html><body><p>Hello <b>world</b></p><script>danger()</script></body></html>",
    ),
    "Hello world",
  );
});
