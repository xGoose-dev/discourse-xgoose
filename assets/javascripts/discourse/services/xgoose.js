import Service, { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { registerDestructor } from "@ember/destroyable";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import {
  createResearchAgent,
  historyStore,
  prepareImages,
} from "../lib/xgoose-agent";

export default class Xgoose extends Service {
  @service currentUser;
  @service appEvents;
  @tracked open = false;
  @tracked busy = false;
  @tracked messages = [];
  @tracked tools = [];
  @tracked attachments = [];
  @tracked history = [];
  @tracked showHistory = false;
  @tracked wide = false;
  @tracked config = null;
  @tracked error = null;
  @tracked logWarning = false;
  @tracked storageWarning = false;
  @tracked includePrivate = false;
  @tracked compacting = false;
  @tracked summary = "";
  @tracked compactions = 0;
  @tracked contextPercent = 0;
  @tracked costUsd = 0;
  costBaseUsd = 0;
  runtime = null;
  sessionId = null;
  userId = null;
  chatId = null;
  title = "";
  createdAt = null;
  context = [];
  interrupted = false;
  generation = 0;
  saveQueue = Promise.resolve();

  constructor() {
    super(...arguments);
    this.appEvents.on("page:changed", this, this.checkIdentity);
    registerDestructor(this, () => {
      this.runtime?.abort();
      this.appEvents.off("page:changed", this, this.checkIdentity);
    });
  }
  get store() {
    if (!this.currentUser) return null;
    return historyStore(
      `${location.origin}${getURL("/")}:${this.currentUser.id}`,
    );
  }
  csrfToken = () =>
    document.querySelector('meta[name="csrf-token"]')?.content || "";
  fetchJson = async (path, options = {}) => {
    const response = await fetch(getURL(path), {
      credentials: "same-origin",
      ...options,
      headers: {
        Accept: "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok)
      throw new Error(
        data.error ||
          (response.status === 429
            ? "rate_limited"
            : `http_${response.status}`),
      );
    return data;
  };
  @action checkIdentity() {
    if (this.userId && this.userId !== this.currentUser?.id) {
      this.reset();
      this.history = [];
      this.open = false;
    }
  }
  snapshot() {
    if (!this.chatId || !this.messages.length) return null;
    return {
      id: this.chatId,
      title: this.title,
      createdAt: this.createdAt,
      updatedAt: Date.now(),
      messages: structuredClone(this.messages),
      tools: structuredClone(this.tools),
      context: structuredClone(
        this.runtime?.agent.state.messages || this.context,
      ),
      summary: this.summary,
      compactions: this.compactions,
      costUsd: this.costUsd,
      contextPercent: this.contextPercent,
      includePrivate: this.includePrivate,
      interrupted: this.busy,
      imageCount: this.messages.reduce(
        (n, m) => n + (m.images?.length || 0),
        0,
      ),
    };
  }
  archive() {
    const snapshot = this.snapshot(),
      store = this.store;
    if (!snapshot || !store) return this.saveQueue;
    this.saveQueue = this.saveQueue
      .catch(() => {})
      .then(() => store.save(snapshot))
      .catch(() => {
        this.storageWarning = true;
      });
    return this.saveQueue;
  }
  @action reset() {
    this.generation++;
    this.runtime?.abort();
    this.runtime = null;
    this.sessionId = null;
    this.messages = [];
    this.tools = [];
    this.attachments = [];
    this.context = [];
    this.busy = false;
    this.error = null;
    this.userId = null;
    this.chatId = null;
    this.title = "";
    this.createdAt = null;
    this.logWarning = false;
    this.includePrivate = false;
    this.showHistory = false;
    this.compacting = false;
    this.summary = "";
    this.compactions = 0;
    this.contextPercent = 0;
    this.costUsd = 0;
    this.costBaseUsd = 0;
    this.interrupted = false;
  }
  @action async newChat() {
    await this.archive();
    this.reset();
    await this.loadConfig();
  }
  @action async toggle() {
    this.checkIdentity();
    if (this.open) {
      await this.archive();
      this.reset();
      this.open = false;
    } else {
      this.reset();
      this.open = true;
      if (this.currentUser) {
        await this.loadConfig();
        await this.refreshHistory();
      }
    }
  }
  async loadConfig() {
    const generation = this.generation,
      sessionId = this.sessionId;
    try {
      const config = await this.fetchJson(
        `/xgoose/config${sessionId ? `?session_id=${sessionId}` : ""}`,
      );
      if (generation !== this.generation) return;
      this.config = config;
      if (sessionId)
        this.costUsd = this.costBaseUsd + (config.session_cost_usd || 0);
    } catch (error) {
      if (generation === this.generation) this.error = error.message;
    }
  }
  async refreshHistory() {
    try {
      this.history = ((await this.store?.list()) || []).map((chat) => ({
        ...chat,
        savedLabel: new Date(chat.updatedAt).toLocaleString(),
        costLabel: `$${(chat.costUsd || 0).toFixed(5)}`,
      }));
    } catch {
      this.storageWarning = true;
    }
  }
  @action async toggleHistory() {
    await this.archive();
    await this.refreshHistory();
    this.showHistory = !this.showHistory;
  }
  @action async restore(id) {
    await this.archive();
    try {
      const saved = await this.store.get(id);
      if (!saved) return;
      this.reset();
      this.userId = this.currentUser.id;
      this.chatId = saved.id;
      this.title = saved.title;
      this.createdAt = saved.createdAt;
      this.messages = saved.messages;
      this.tools = saved.tools;
      this.context = saved.context;
      this.summary = saved.summary || "";
      this.compactions = saved.compactions || 0;
      this.contextPercent = saved.contextPercent || 0;
      this.costUsd = saved.costUsd || 0;
      this.costBaseUsd = this.costUsd;
      this.includePrivate = saved.includePrivate;
      this.interrupted = saved.interrupted;
      this.showHistory = false;
      await this.loadConfig();
    } catch {
      this.storageWarning = true;
    }
  }
  @action async deleteHistory(id) {
    try {
      await this.store.delete(id);
      if (this.chatId === id) this.reset();
      await this.refreshHistory();
    } catch {
      this.storageWarning = true;
    }
  }
  @action async attach(files) {
    try {
      if (this.attachments.length + files.length > 2)
        throw new Error("image_limit");
      this.attachments = [...this.attachments, ...(await prepareImages(files))];
      this.error = null;
    } catch (error) {
      this.error = error.message;
    }
  }
  @action removeAttachment(id) {
    this.attachments = this.attachments.filter((a) => a.id !== id);
  }
  @action toggleWide() {
    this.wide = !this.wide;
  }
  @action compact() {
    this.runtime?.requestCompaction();
  }
  @action async send(text) {
    this.checkIdentity();
    if (
      this.busy ||
      !this.currentUser ||
      (!text?.trim() && !this.attachments.length)
    )
      return;
    const images = this.attachments;
    this.attachments = [];
    text = text?.trim() || i18n("xgoose.image_prompt");
    this.busy = true;
    this.error = null;
    this.userId = this.currentUser.id;
    if (!this.chatId) {
      this.chatId = crypto.randomUUID();
      this.title = text.slice(0, 80);
      this.createdAt = Date.now();
    }
    const generation = this.generation;
    try {
      if (!this.config) await this.loadConfig();
      if (!this.config?.configured) throw new Error("not_configured");
      if (!this.runtime) {
        const session = await this.fetchJson("/xgoose/sessions", {
          method: "POST",
          body: {},
        });
        if (generation !== this.generation) return;
        this.sessionId = session.id;
        this.runtime = createResearchAgent({
          config: this.config,
          sessionId: session.id,
          fetchJson: this.fetchJson,
          csrfToken: this.csrfToken,
          endpoint: getURL(`/xgoose/sessions/${session.id}`),
          initialMessages: this.context,
          forceSummary: this.interrupted,
          url: (path) => new URL(getURL(path), location.origin).href,
          allowPrivate: () => this.includePrivate,
          currentTopic: () =>
            Number(location.pathname.match(/\/t\/(?:[^/]+\/)?(\d+)/)?.[1]) ||
            null,
          onContext: (estimate, limit) => {
            if (generation === this.generation)
              this.contextPercent = Math.min(
                100,
                Math.round((estimate / limit) * 100),
              );
          },
          onCompaction: (result) => {
            if (generation !== this.generation) return;
            this.compacting = result.running;
            if (!result.running) {
              this.summary = result.summary;
              this.compactions++;
              this.archive();
            }
          },
          onLogFailure: () => {
            if (generation === this.generation) this.logWarning = true;
          },
          onEvent: (event) => {
            if (generation !== this.generation) return;
            const message = event.message;
            if (
              message &&
              ["message_start", "message_update", "message_end"].includes(
                event.type,
              ) &&
              ["user", "assistant"].includes(message.role)
            ) {
              const parts =
                typeof message.content === "string"
                  ? [{ type: "text", text: message.content }]
                  : message.content || [];
              const content = parts
                .filter((c) => c.type === "text")
                .map((c) => c.text)
                .join("");
              const attached = parts
                .filter((c) => c.type === "image")
                .map((c, n) => ({
                  id: n,
                  dataUrl: `data:${c.mimeType};base64,${c.data}`,
                }));
              if (content || attached.length || message.errorMessage) {
                const id = `${message.role}:${message.timestamp}`;
                const item = {
                  id,
                  role: message.role,
                  content,
                  images: attached,
                  error: message.errorMessage,
                };
                this.messages = this.messages.some((m) => m.id === id)
                  ? this.messages.map((m) => (m.id === id ? item : m))
                  : [...this.messages, item];
              }
            }
            if (event.type === "tool_execution_start")
              this.tools = [
                ...this.tools,
                {
                  id: event.toolCallId,
                  name: event.toolName,
                  running: true,
                  details: JSON.stringify(event.args, null, 2),
                },
              ];
            if (event.type === "tool_execution_end")
              this.tools = this.tools.map((t) =>
                t.id === event.toolCallId
                  ? {
                      ...t,
                      running: false,
                      failed: event.isError,
                      details: JSON.stringify(
                        event.result?.details || event.result,
                        null,
                        2,
                      ),
                    }
                  : t,
              );
            if (
              ["message_end", "tool_execution_end", "agent_end"].includes(
                event.type,
              )
            )
              this.archive();
          },
        });
      }
      await this.runtime.prompt(text, images);
    } catch (error) {
      if (generation === this.generation) this.error = error.message;
    } finally {
      if (generation === this.generation) {
        await this.loadConfig();
        if (generation === this.generation) {
          this.busy = false;
          this.compacting = false;
          await this.archive();
        }
      }
    }
  }
  @action stop() {
    this.runtime?.abort();
  }
  @action togglePrivate(event) {
    this.includePrivate = event.target.checked;
  }
}
