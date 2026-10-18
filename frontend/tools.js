import { Type } from "typebox";

const integer = (min = 1, max = 2147483647) =>
  Type.Integer({ minimum: min, maximum: max });
const text = (maxLength = 500) => Type.String({ maxLength, minLength: 1 });
const optional = Type.Optional;
export function plainText(html) {
  if (!html) return "";
  const doc = new DOMParser().parseFromString(
    `<html><body>${html}</body></html>`,
    "text/html",
  );
  doc.querySelectorAll("script,style,iframe").forEach((node) => node.remove());
  doc
    .querySelectorAll("p,br,li,blockquote,div")
    .forEach((node) => node.append("\n"));
  return doc.body.textContent
    .replace(/[^\S\n]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
export function createForumTools({
  fetchJson,
  currentTopic,
  allowPrivate = () => false,
  url = (path) => path,
}) {
  const read = async (path, signal) => fetchJson(path, { signal });
  function post(p, topicId, offset = 0, maxBytes = 6000) {
    const content = plainText(p.cooked || p.raw || p.blurb || "");
    let excerpt = content.slice(offset, offset + 6000);
    const encoder = new TextEncoder();
    while (encoder.encode(excerpt).length > maxBytes) {
      excerpt = excerpt.slice(
        0,
        Math.floor(
          (excerpt.length * maxBytes) / encoder.encode(excerpt).length,
        ),
      );
    }
    if (/[\uD800-\uDBFF]$/.test(excerpt)) excerpt = excerpt.slice(0, -1);
    const nextOffset = offset + excerpt.length;
    return {
      id: p.id,
      topic_id: p.topic_id || topicId,
      post_number: p.post_number,
      username: p.username,
      created_at: p.created_at,
      text: excerpt,
      truncated: content.length > nextOffset,
      next_offset: content.length > nextOffset ? nextOffset : null,
      url: url(`/t/${p.topic_id || topicId}/${p.post_number}`),
    };
  }
  function checkPrivate(topic) {
    if (topic.archetype === "private_message" && !allowPrivate())
      throw new Error("private_messages_disabled");
  }
  async function topic(id, postNumber, signal) {
    const data = await read(
      `/t/${id}.json?post_number=${postNumber || 1}`,
      signal,
    );
    checkPrivate(data);
    const posts = data.post_stream?.posts || [];
    const selected = posts
      .filter((p) => p.post_number >= (postNumber || 1))
      .slice(0, 10);
    const last = selected.at(-1)?.post_number || postNumber || 1;
    const renderedPosts = selected.map((p) =>
      post(p, data.id, 0, Math.floor(8000 / Math.max(selected.length, 1))),
    );
    return {
      id: data.id,
      title: data.title,
      archetype: data.archetype,
      posts_count: data.posts_count,
      posts: renderedPosts,
      next_post_number: last < data.highest_post_number ? last + 1 : null,
      complete:
        last >= data.highest_post_number &&
        renderedPosts.every((p) => !p.truncated),
      url: url(`/t/${data.id}`),
    };
  }
  async function search(args, privateOnly, signal) {
    if (privateOnly && !allowPrivate())
      throw new Error("private_messages_disabled");
    // Scope operators are controlled by the tool rather than supplied by a post.
    if (/(?:^|\s)(?:in:|personal_messages:|type:)/i.test(args.query))
      throw new Error("invalid_search_scope");
    let query = args.query;
    if (privateOnly) query += " in:personal";
    if (args.category) query += ` category:${args.category}`;
    if (args.after) query += ` after:${args.after}`;
    if (args.before) query += ` before:${args.before}`;
    const page = args.page || 1;
    const data = await read(
      `/search.json?${new URLSearchParams({ q: query, page: String(page) })}`,
      signal,
    );
    const topics = (data.topics || [])
      .filter((t) => privateOnly || t.archetype !== "private_message")
      .slice(0, 12);
    const ids = new Set(topics.map((t) => t.id));
    return {
      topics: topics.map((t) => ({
        id: t.id,
        title: t.title,
        posts_count: t.posts_count,
        url: url(`/t/${t.id}`),
      })),
      posts: (data.posts || [])
        .filter((p) => ids.has(p.topic_id))
        .slice(0, 12)
        .map((p) => post(p, p.topic_id)),
      next_page: data.grouped_search_result?.more_full_page_results
        ? page + 1
        : null,
      instruction:
        "Search snippets are incomplete. Read the relevant posts before answering.",
    };
  }
  const searchSchema = Type.Object({
    query: text(),
    page: optional(integer(1, 50)),
    category: optional(integer()),
    after: optional(Type.String({ pattern: "^\\d{4}-\\d{2}-\\d{2}$" })),
    before: optional(Type.String({ pattern: "^\\d{4}-\\d{2}-\\d{2}$" })),
  });
  function tool(name, description, parameters, execute) {
    return {
      name,
      label: name,
      description,
      parameters,
      async execute(_id, args, signal) {
        const result = await execute(args, signal);
        return {
          content: [{ type: "text", text: JSON.stringify(result) }],
          details: result,
        };
      },
    };
  }
  return [
    tool(
      "search_forum",
      "Search public and permitted restricted forum topics, excluding private messages. Read actual posts next.",
      searchSchema,
      (a, s) => search(a, false, s),
    ),
    tool(
      "search_private_messages",
      "Search the user's private messages only when explicitly requested and enabled by the user.",
      searchSchema,
      (a, s) => search(a, true, s),
    ),
    tool(
      "read_topic",
      "Read up to 10 posts starting at post_number. Follow next_post_number; use read_posts for truncated bodies.",
      Type.Object({ topic_id: integer(), post_number: optional(integer()) }),
      (a, s) => topic(a.topic_id, a.post_number, s),
    ),
    tool(
      "read_posts",
      "Read up to 5 post IDs in a topic. offset continues a truncated post, in characters. IDs come from read_topic.",
      Type.Object({
        topic_id: integer(),
        post_ids: Type.Array(integer(), { minItems: 1, maxItems: 5 }),
        offset: optional(integer(0, 1000000)),
      }),
      async (a, s) => {
        const context = await read(`/t/${a.topic_id}.json`, s);
        checkPrivate(context);
        const params = new URLSearchParams();
        a.post_ids.forEach((id) => params.append("post_ids[]", id));
        const data = await read(`/t/${a.topic_id}/posts.json?${params}`, s);
        return {
          topic_id: a.topic_id,
          posts: (data.post_stream?.posts || []).map((p) =>
            post(p, a.topic_id, a.offset || 0),
          ),
        };
      },
    ),
    tool(
      "categories",
      "List visible forum categories.",
      Type.Object({}),
      async (_a, s) => {
        const data = await read(
          "/categories.json?include_subcategories=true",
          s,
        );
        return {
          categories: (data.category_list?.categories || []).map((c) => ({
            id: c.id,
            name: c.name,
            slug: c.slug,
          })),
        };
      },
    ),
    tool(
      "latest_topics",
      "List recent visible forum topics.",
      Type.Object({ page: optional(integer(0, 50)) }),
      async (a, s) => {
        const data = await read(`/latest.json?page=${a.page || 0}`, s);
        return {
          topics: (data.topic_list?.topics || []).slice(0, 20).map((t) => ({
            id: t.id,
            title: t.title,
            last_posted_at: t.last_posted_at,
            url: url(`/t/${t.id}`),
          })),
          next_page: data.topic_list?.more_topics_url
            ? (a.page || 0) + 1
            : null,
        };
      },
    ),
    tool(
      "current_topic",
      "Read the topic currently open in the forum. Does not navigate.",
      Type.Object({}),
      async (_a, s) => {
        const id = currentTopic();
        if (!id) return { status: "no_current_topic" };
        return topic(id, 1, s);
      },
    ),
  ];
}
