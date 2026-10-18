import Service, { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { registerDestructor } from "@ember/destroyable";
import getURL from "discourse/lib/get-url";
import { createResearchAgent } from "../lib/xgoose-agent";

export default class Xgoose extends Service {
  @service currentUser;
  @service appEvents;
  @tracked open = false;
  @tracked busy = false;
  @tracked messages = [];
  @tracked tools = [];
  @tracked config = null;
  @tracked error = null;
  @tracked logWarning = false;
  @tracked includePrivate = false;
  runtime = null;
  sessionId = null;
  userId = null;
  generation = 0;

  constructor() {
    super(...arguments);
    this.appEvents.on("page:changed", this, this.checkIdentity);
    registerDestructor(this, () => {
      this.runtime?.abort();
      this.appEvents.off("page:changed", this, this.checkIdentity);
    });
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
    if (this.userId && this.userId !== this.currentUser?.id) this.reset();
  }
  @action reset() {
    this.generation++;
    this.runtime?.abort();
    this.runtime = null;
    this.sessionId = null;
    this.messages = [];
    this.tools = [];
    this.busy = false;
    this.error = null;
    this.config = null;
    this.userId = null;
    this.logWarning = false;
    this.includePrivate = false;
  }
  @action newChat() {
    this.reset();
    this.loadConfig();
  }
  @action async toggle() {
    this.checkIdentity();
    this.open = !this.open;
    if (this.open && this.currentUser && !this.config) await this.loadConfig();
  }
  async loadConfig() {
    try {
      this.config = await this.fetchJson("/xgoose/config");
    } catch (error) {
      this.error = error.message;
    }
  }
  @action async send(text) {
    this.checkIdentity();
    if (!text?.trim() || this.busy || !this.currentUser) return;
    this.busy = true;
    this.error = null;
    this.userId = this.currentUser.id;
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
          url: (path) => getURL(path),
          allowPrivate: () => this.includePrivate,
          currentTopic: () =>
            Number(location.pathname.match(/\/t\/(?:[^/]+\/)?(\d+)/)?.[1]) ||
            null,
          onLogFailure: () => {
            if (generation === this.generation) this.logWarning = true;
          },
          onEvent: (event, state) => {
            if (generation !== this.generation) return;
            if (
              [
                "message_update",
                "message_end",
                "message_start",
                "agent_end",
              ].includes(event.type)
            ) {
              const list = state.messages.filter(
                (m) => m.role === "user" || m.role === "assistant",
              );
              if (
                state.streamingMessage &&
                !list.includes(state.streamingMessage)
              )
                list.push(state.streamingMessage);
              this.messages = list
                .map((m, index) => ({
                  id: index,
                  role: m.role,
                  content:
                    typeof m.content === "string"
                      ? m.content
                      : (m.content || [])
                          .filter((c) => c.type === "text")
                          .map((c) => c.text)
                          .join(""),
                  error: m.errorMessage,
                }))
                .filter((m) => m.content || m.error);
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
          },
        });
      }
      await this.runtime.prompt(text.trim());
    } catch (error) {
      if (generation === this.generation) this.error = error.message;
    } finally {
      if (generation === this.generation) {
        this.busy = false;
        await this.loadConfig();
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
