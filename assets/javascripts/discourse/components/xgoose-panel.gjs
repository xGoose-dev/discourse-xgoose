import Component from "@glimmer/component";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { concat } from "@ember/helper";
import { fn } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { i18n } from "discourse-i18n";
import XgooseMessage from "./xgoose-message";
export default class XgoosePanel extends Component {
  @service xgoose;
  @service currentUser;
  @tracked draft = "";
  followOutput = true;
  get remaining() {
    return `$${(this.xgoose.config?.quota?.remaining_usd || 0).toFixed(2)}`;
  }
  get daily() {
    return `$${(this.xgoose.config?.quota?.limit_usd ?? 2).toFixed(2)}`;
  }
  get cost() {
    return `$${this.xgoose.costUsd.toFixed(5)}`;
  }
  get model() {
    return this.xgoose.config?.model || "Luna";
  }
  get resetTime() {
    const d = this.xgoose.config?.quota?.resets_at;
    return d ? new Date(d).toLocaleString() : "";
  }
  get errorText() {
    return this.xgoose.error
      ? i18n(`xgoose.errors.${this.xgoose.error}`, {
          defaultValue: i18n("xgoose.errors.generic"),
        })
      : "";
  }
  userScrollingUntil = 0;
  observer = null;
  constructor() {
    super(...arguments);
    registerDestructor(this, () => this.observer?.disconnect());
  }
  @action scrollIntent(event) {
    this.userScrollingUntil = performance.now() + 1500;
    if (event.type === "wheel" && event.deltaY < 0) this.followOutput = false;
  }
  @action watchScroll(event) {
    if (performance.now() > this.userScrollingUntil) return;
    const e = event.currentTarget;
    this.followOutput = e.scrollHeight - e.scrollTop - e.clientHeight < 100;
  }
  @action observeThread(element) {
    this.observer?.disconnect();
    this.observer = new ResizeObserver(() => this.scrollThread(element));
    this.observer.observe(element.firstElementChild);
    this.scrollThread(element);
  }
  @action scrollThread(element) {
    if (this.followOutput)
      requestAnimationFrame(() => {
        if (element.isConnected) element.scrollTop = element.scrollHeight;
      });
  }
  @action updateDraft(event) {
    this.draft = event.target.value;
  }
  @action send(event) {
    event.preventDefault();
    if (this.xgoose.busy) return;
    const text = this.draft;
    this.draft = "";
    this.followOutput = true;
    this.xgoose.send(text);
  }
  @action shortcut(event) {
    this.xgoose.send(
      i18n(`xgoose.prompts.${event.currentTarget.dataset.prompt}`),
    );
  }
  @action toggle() {
    this.draft = "";
    this.xgoose.toggle();
  }
  @action async newChat() {
    this.draft = "";
    await this.xgoose.newChat();
  }
  @action keydown(event) {
    if (event.key === "Escape") {
      const details = event.currentTarget.querySelector(".xgoose-info[open]");
      if (details) {
        details.removeAttribute("open");
        details.querySelector("summary").focus();
        return;
      }
      this.toggle();
      document.querySelector(".xgoose-launcher")?.focus();
    }
    if (
      event.key === "Enter" &&
      !event.shiftKey &&
      !event.isComposing &&
      event.target.tagName === "TEXTAREA"
    )
      this.send(event);
  }
  @action focus(element) {
    (
      element.querySelector("textarea") || element.querySelector("button")
    )?.focus();
  }
  @action chooseImage() {
    document.querySelector("#xgoose-images")?.click();
  }
  @action files(event) {
    this.xgoose.attach(Array.from(event.target.files));
    event.target.value = "";
  }
  @action paste(event) {
    const files = Array.from(event.clipboardData?.files || []).filter((f) =>
      f.type.startsWith("image/"),
    );
    if (files.length) {
      event.preventDefault();
      this.xgoose.attach(files);
    }
  }
  <template>
    <button
      type="button"
      class="xgoose-launcher"
      aria-label={{i18n "xgoose.open"}}
      aria-expanded={{this.xgoose.open}}
      aria-controls="xgoose-panel"
      {{on "click" this.toggle}}
    >✦</button>
    {{#if this.xgoose.open}}
      <section
        id="xgoose-panel"
        class="xgoose-panel {{if this.xgoose.wide 'is-wide'}}"
        aria-label={{i18n "xgoose.title"}}
        {{on "keydown" this.keydown}}
        {{didInsert this.focus}}
      >
        <header class="xgoose-header">
          <span class="xgoose-brand-mark" aria-hidden="true">✦</span><strong
            class="xgoose-brand"
          >xGoose</strong>
          <div class="xgoose-header-actions">
            <button
              type="button"
              aria-label={{i18n "xgoose.history"}}
              title={{i18n "xgoose.history"}}
              aria-pressed={{this.xgoose.showHistory}}
              {{on "click" this.xgoose.toggleHistory}}
            >◷</button>
            <button
              type="button"
              aria-label={{i18n "xgoose.new_chat"}}
              title={{i18n "xgoose.new_chat"}}
              {{on "click" this.newChat}}
            >＋</button>
            <button
              type="button"
              class="xgoose-expand"
              aria-label={{i18n "xgoose.expand"}}
              title={{i18n "xgoose.expand"}}
              {{on "click" this.xgoose.toggleWide}}
            >⤢</button>
            <button
              type="button"
              aria-label={{i18n "xgoose.close"}}
              title={{i18n "xgoose.close"}}
              {{on "click" this.toggle}}
            >×</button>
          </div>
        </header>
        {{#if this.currentUser}}
          {{#if this.xgoose.showHistory}}
            <div class="xgoose-history"><h2>{{i18n "xgoose.history"}}</h2><p
              >{{i18n "xgoose.history_hint"}}</p>
              {{#each this.xgoose.history key="id" as |chat|}}<div
                  class="xgoose-history-row"
                ><button
                    type="button"
                    {{on "click" (fn this.xgoose.restore chat.id)}}
                  ><strong>{{chat.title}}</strong><small
                    >{{chat.savedLabel}}</small></button><button
                    type="button"
                    aria-label={{i18n "xgoose.delete_chat"}}
                    title={{i18n "xgoose.delete_chat"}}
                    {{on "click" (fn this.xgoose.deleteHistory chat.id)}}
                  >×</button></div>{{else}}<p>{{i18n
                    "xgoose.history_empty"
                  }}</p>{{/each}}
            </div>
          {{else}}
            <div
              class="xgoose-thread"
              {{on "scroll" this.watchScroll}}
              {{on "wheel" this.scrollIntent}}
              {{on "touchmove" this.scrollIntent}}
              {{on "pointerdown" this.scrollIntent}}
              {{didInsert this.observeThread}}
              {{didUpdate
                this.scrollThread
                this.xgoose.messages
                this.xgoose.tools
              }}
              role="log"
              aria-label={{i18n "xgoose.conversation"}}
              aria-live="polite"
              aria-busy={{this.xgoose.busy}}
            >
              <div class="xgoose-thread-content">
                {{#unless this.xgoose.messages.length}}<div
                    class="xgoose-welcome"
                  ><h2>{{i18n "xgoose.welcome"}}</h2><p>{{i18n
                        "xgoose.welcome_hint"
                      }}</p><div class="xgoose-shortcuts">
                      <button
                        type="button"
                        data-prompt="summarize"
                        {{on "click" this.shortcut}}
                      >{{i18n "xgoose.summarize"}}</button>
                      <button
                        type="button"
                        data-prompt="related"
                        {{on "click" this.shortcut}}
                      >{{i18n "xgoose.related"}}</button>
                      <button
                        type="button"
                        data-prompt="recent"
                        {{on "click" this.shortcut}}
                      >{{i18n "xgoose.recent"}}</button>
                    </div></div>{{/unless}}
                {{#each
                  this.xgoose.messages key="id"
                  as |message|
                }}<XgooseMessage @message={{message}} />{{/each}}
                {{#if this.xgoose.busy}}<div class="xgoose-thinking"><span
                    >✦</span>{{if
                      this.xgoose.compacting
                      (i18n "xgoose.compacting")
                      (i18n "xgoose.thinking")
                    }}</div>{{/if}}
                {{#if this.xgoose.tools.length}}<details
                    class="xgoose-tools"
                  ><summary>{{i18n "xgoose.research_steps"}}
                      <span>{{this.xgoose.tools.length}}</span></summary>{{#each
                      this.xgoose.tools key="id"
                      as |tool|
                    }}<details><summary>{{i18n
                            (concat "xgoose.tools." tool.name)
                          }}
                          ·
                          {{if
                            tool.running
                            (i18n "xgoose.running")
                            (if
                              tool.failed
                              (i18n "xgoose.failed")
                              (i18n "xgoose.done")
                            )
                          }}</summary><pre
                        >{{tool.details}}</pre></details>{{/each}}</details>{{/if}}
              </div>
            </div>
            {{#if this.xgoose.error}}<p
                class="xgoose-error"
                role="alert"
              >{{this.errorText}}</p>{{/if}}
            {{#if this.xgoose.logWarning}}<p class="xgoose-error">{{i18n
                  "xgoose.log_warning"
                }}</p>{{/if}}
            <form class="xgoose-composer" {{on "submit" this.send}}>
              {{#if this.xgoose.attachments.length}}<div
                  class="xgoose-attachments"
                >{{#each this.xgoose.attachments key="id" as |image|}}<div><img
                        src={{image.dataUrl}}
                        alt={{image.name}}
                      /><button
                        type="button"
                        aria-label={{i18n "xgoose.remove_image"}}
                        {{on
                          "click"
                          (fn this.xgoose.removeAttachment image.id)
                        }}
                      >×</button></div>{{/each}}</div>{{/if}}
              <label class="sr-only" for="xgoose-input">{{i18n
                  "xgoose.input"
                }}</label><textarea
                id="xgoose-input"
                value={{this.draft}}
                rows="2"
                maxlength="12000"
                placeholder={{i18n "xgoose.placeholder"}}
                {{on "input" this.updateDraft}}
                {{on "paste" this.paste}}
              ></textarea>
              <div class="xgoose-compose-actions"><input
                  id="xgoose-images"
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  multiple
                  hidden
                  {{on "change" this.files}}
                /><button
                  type="button"
                  class="xgoose-attach"
                  aria-label={{i18n "xgoose.attach"}}
                  title={{i18n "xgoose.attach"}}
                  disabled={{this.xgoose.busy}}
                  {{on "click" this.chooseImage}}
                >＋</button><div class="xgoose-send-spacer"></div>{{#if
                  this.xgoose.busy
                }}<button
                    type="button"
                    class="xgoose-send"
                    {{on "click" this.xgoose.stop}}
                    aria-label={{i18n "xgoose.stop"}}
                  >■</button>{{else}}<button
                    type="submit"
                    class="xgoose-send"
                    aria-label={{i18n "xgoose.send"}}
                  >↑</button>{{/if}}</div>
            </form>
          {{/if}}
          {{#if this.xgoose.storageWarning}}<p class="xgoose-error">{{i18n
                "xgoose.storage_warning"
              }}</p>{{/if}}
          <footer class="xgoose-footer">
            <span title={{i18n "xgoose.resets" time=this.resetTime}}>{{i18n
                "xgoose.budget_remaining"
                amount=this.remaining
              }}</span>
            <details class="xgoose-info"><summary>{{i18n
                  "xgoose.details"
                }}</summary><div class="xgoose-info-body">
                <div class="xgoose-info-row"><span>{{i18n
                      "xgoose.model"
                    }}</span><span>{{this.model}}</span></div>
                <div class="xgoose-info-row"><span>{{i18n
                      "xgoose.budget"
                    }}</span><span>{{this.remaining}}
                    /
                    {{this.daily}}</span></div>
                <div class="xgoose-info-row"><span>{{i18n
                      "xgoose.admin.daily_limit"
                    }}</span><strong
                  >${{this.xgoose.config.quota.base_limit_usd}}</strong></div>
                <div class="xgoose-info-row"><span>{{i18n
                      "xgoose.admin.today_bonus"
                    }}</span><strong
                  >${{this.xgoose.config.quota.bonus_usd}}</strong></div>
                <p>{{i18n "xgoose.resets" time=this.resetTime}}</p>
                <div class="xgoose-context"><span>{{i18n
                      "xgoose.chat_cost"
                      cost=this.cost
                    }}</span><span>{{i18n
                      "xgoose.context"
                      percent=this.xgoose.contextPercent
                    }}</span></div>
                <p title={{i18n "xgoose.auto_summary"}}>{{i18n
                    "xgoose.summaries"
                    count=this.xgoose.compactions
                  }}</p>
                <label class="xgoose-private"><input
                    type="checkbox"
                    checked={{this.xgoose.includePrivate}}
                    disabled={{this.xgoose.busy}}
                    {{on "change" this.xgoose.togglePrivate}}
                  />{{i18n "xgoose.include_private"}}</label>
                {{#if this.xgoose.summary}}<details
                    class="xgoose-summary"
                  ><summary>{{i18n "xgoose.summary"}}</summary><p
                    >{{this.xgoose.summary}}</p></details>{{/if}}
                <p class="xgoose-privacy">{{i18n "xgoose.privacy"}}</p>
              </div></details>
          </footer>
        {{else}}<p class="xgoose-welcome">{{i18n
              "xgoose.login_required"
            }}</p>{{/if}}
      </section>
    {{/if}}
  </template>
}
