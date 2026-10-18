import Component from "@glimmer/component";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { concat } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { i18n } from "discourse-i18n";
import XgooseMessage from "./xgoose-message";
export default class XgoosePanel extends Component {
  @service xgoose;
  @service currentUser;
  @tracked draft = "";
  followOutput = true;
  @action watchScroll(event) {
    const e = event.currentTarget;
    this.followOutput = e.scrollHeight - e.scrollTop - e.clientHeight < 100;
  }
  @action scrollThread(element) {
    if (this.followOutput) requestAnimationFrame(() => { if (element.isConnected) element.scrollTop = element.scrollHeight; });
  }
  get remaining() { return this.xgoose.config?.quota?.remaining?.toLocaleString() || "0"; }
  get resetTime() { const date = this.xgoose.config?.quota?.resets_at; return date ? new Date(date).toLocaleString() : ""; }
  get errorText() { return this.xgoose.error ? i18n(`xgoose.errors.${this.xgoose.error}`, { defaultValue: i18n("xgoose.errors.generic") }) : ""; }
  @action updateDraft(event) { this.draft = event.target.value; }
  @action send(event) { event.preventDefault(); const text = this.draft; this.draft = ""; this.xgoose.send(text); }
  @action shortcut(event) { this.xgoose.send(i18n(`xgoose.prompts.${event.currentTarget.dataset.prompt}`)); }
  @action keydown(event) {
    if (event.key === "Escape") { this.xgoose.open = false; document.querySelector(".xgoose-launcher")?.focus(); }
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing && event.target.tagName === "TEXTAREA") this.send(event);
  }
  @action focus(element) { element.querySelector("textarea,button")?.focus(); }
  <template>
    <button type="button" class="xgoose-launcher" aria-label={{i18n "xgoose.open"}} aria-expanded={{this.xgoose.open}} aria-controls="xgoose-panel" {{on "click" this.xgoose.toggle}}>✦</button>
    {{#if this.xgoose.open}}
      <section id="xgoose-panel" class="xgoose-panel" aria-label={{i18n "xgoose.title"}} {{on "keydown" this.keydown}} {{didInsert this.focus}}>
        <header>
          <div><strong>xGoose</strong><span>{{i18n "xgoose.subtitle"}}</span></div>
          <button type="button" title={{i18n "xgoose.new_chat"}} {{on "click" this.xgoose.newChat}}>{{i18n "xgoose.new_chat"}}</button>
          <button type="button" aria-label={{i18n "xgoose.close"}} {{on "click" this.xgoose.toggle}}>×</button>
        </header>
        {{#if this.currentUser}}
          <div class="xgoose-quota">{{i18n "xgoose.remaining" count=this.remaining}}<span title={{this.resetTime}}>{{i18n "xgoose.resets" time=this.resetTime}}</span></div>
          <div class="xgoose-thread" {{on "scroll" this.watchScroll}} {{didInsert this.scrollThread}} {{didUpdate this.scrollThread this.xgoose.messages this.xgoose.tools}} role="log" aria-label={{i18n "xgoose.conversation"}} aria-live="polite" aria-busy={{this.xgoose.busy}}>
            {{#unless this.xgoose.messages.length}}
              <div class="xgoose-welcome"><h2>{{i18n "xgoose.welcome"}}</h2><p>{{i18n "xgoose.welcome_hint"}}</p>
                <button type="button" data-prompt="summarize" {{on "click" this.shortcut}}>{{i18n "xgoose.summarize"}}</button>
                <button type="button" data-prompt="related" {{on "click" this.shortcut}}>{{i18n "xgoose.related"}}</button>
                <button type="button" data-prompt="recent" {{on "click" this.shortcut}}>{{i18n "xgoose.recent"}}</button>
              </div>
            {{/unless}}
            {{#each this.xgoose.messages key="id" as |message|}}<XgooseMessage @message={{message}} />{{/each}}
            {{#if this.xgoose.tools.length}}
              <details class="xgoose-tools"><summary>{{i18n "xgoose.research_steps"}}</summary>
                {{#each this.xgoose.tools key="id" as |tool|}}<details><summary>{{i18n (concat "xgoose.tools." tool.name)}} — {{if tool.running (i18n "xgoose.running") (if tool.failed (i18n "xgoose.failed") (i18n "xgoose.done"))}}</summary><pre>{{tool.details}}</pre></details>{{/each}}
              </details>
            {{/if}}
          </div>
          {{#if this.xgoose.error}}<p class="xgoose-error" role="alert">{{this.errorText}}</p>{{/if}}
          {{#if this.xgoose.logWarning}}<p class="xgoose-error">{{i18n "xgoose.log_warning"}}</p>{{/if}}
          <form {{on "submit" this.send}}>
            <label class="xgoose-private"><input type="checkbox" checked={{this.xgoose.includePrivate}} disabled={{this.xgoose.busy}} {{on "change" this.xgoose.togglePrivate}} />{{i18n "xgoose.include_private"}}</label>
            <label class="sr-only" for="xgoose-input">{{i18n "xgoose.input"}}</label>
            <textarea id="xgoose-input" value={{this.draft}} rows="3" maxlength="12000" placeholder={{i18n "xgoose.placeholder"}} {{on "input" this.updateDraft}}></textarea>
            <div class="xgoose-compose-actions"><small>{{i18n "xgoose.privacy"}}</small>
              {{#if this.xgoose.busy}}<button type="button" {{on "click" this.xgoose.stop}}>{{i18n "xgoose.stop"}}</button>{{else}}<button type="submit" class="btn btn-primary">{{i18n "xgoose.send"}}</button>{{/if}}
            </div>
          </form>
        {{else}}<p class="xgoose-welcome">{{i18n "xgoose.login_required"}}</p>{{/if}}
      </section>
    {{/if}}
  </template>
}
