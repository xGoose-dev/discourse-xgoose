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
      <div class="cooked" {{on "click" this.navigate}}>{{this.cooked}}</div>
    </article>
  </template>
}
