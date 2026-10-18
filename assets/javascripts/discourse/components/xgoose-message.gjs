import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import { tracked } from "@glimmer/tracking";
import { cook } from "discourse/lib/text";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { eq } from "discourse/truth-helpers";
import { action } from "@ember/object";
import { i18n } from "discourse-i18n";
export default class XgooseMessage extends Component {
  @tracked cooked = null;
  revision = 0;
  @action async renderContent() {
    const revision = ++this.revision;
    const result = await cook(this.args.message.content || "");
    if (!this.isDestroying && revision === this.revision) this.cooked = htmlSafe(result);
  }
  <template>
    <article class="xgoose-message" data-role={{@message.role}} {{didInsert this.renderContent}} {{didUpdate this.renderContent @message.content}}>
      <strong>{{if (eq @message.role "user") (i18n "xgoose.you") "xGoose"}}</strong>
      <div class="cooked">{{this.cooked}}</div>
    </article>
  </template>
}
