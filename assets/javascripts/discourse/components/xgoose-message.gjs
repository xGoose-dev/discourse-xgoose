import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import { tracked } from "@glimmer/tracking";
import { cook } from "discourse/lib/text";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { eq } from "discourse/truth-helpers";
import { action } from "@ember/object";
import { i18n } from "discourse-i18n";
import { on } from "@ember/modifier";
import DiscourseURL from "discourse/lib/url";
export default class XgooseMessage extends Component {
  @tracked cooked = null;
  @tracked copied = false;
  @action async copy() {
    try {
      await navigator.clipboard.writeText(this.args.message.content);
      this.copied = true;
    } catch {
      this.copied = false;
    }
  }
  revision = 0;
  @action navigate(event) {
    const anchor = event.target.closest("a");
    if (
      !anchor ||
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      anchor.target === "_blank"
    )
      return;
    const target = new URL(anchor.href, location.href);
    if (target.origin === location.origin) {
      event.preventDefault();
      DiscourseURL.routeTo(target.pathname + target.search + target.hash);
    }
  }
  @action async renderContent() {
    const revision = ++this.revision;
    const result = await cook(this.args.message.content || "");
    if (!this.isDestroying && revision === this.revision)
      this.cooked = htmlSafe(result);
  }
  <template>
    <article
      class="xgoose-message"
      data-role={{@message.role}}
      {{didInsert this.renderContent}}
      {{didUpdate this.renderContent @message.content}}
    >
      <strong>{{if
          (eq @message.role "user")
          (i18n "xgoose.you")
          "xGoose"
        }}</strong>
      {{#if @message.images.length}}<div class="xgoose-message-images">{{#each
            @message.images
            as |image|
          }}<img
              src={{image.dataUrl}}
              alt={{i18n "xgoose.attached_image"}}
            />{{/each}}</div>{{/if}}
      <div class="cooked" {{on "click" this.navigate}}>{{this.cooked}}</div>
      {{#if (eq @message.role "assistant")}}<button
          type="button"
          class="xgoose-copy"
          {{on "click" this.copy}}
        >{{if
            this.copied
            (i18n "xgoose.copied")
            (i18n "xgoose.copy")
          }}</button>{{/if}}
    </article>
  </template>
}
