import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, hash } from "@ember/helper";
import { service } from "@ember/service";
import { registerDestructor } from "@ember/destroyable";
import { eq, not } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import Chart from "discourse/admin/components/chart";
import UserChooser from "discourse/select-kit/components/user-chooser";
import XgooseMessage from "discourse/plugins/discourse-xgoose/discourse/components/xgoose-message";
const ROOT = "/admin/plugins/discourse-xgoose";
const t = (key) => i18n(`xgoose.admin.${key}`);
const dollars = (micro) => `$${(Number(micro || 0) / 1e6).toFixed(6)}`;
const pretty = (value) => JSON.stringify(value, null, 2);

export default class XgooseAdmin extends Component {
  @service router;
  @service currentUser;
  @service dialog;
  @tracked data;
  @tracked loading = true;
  @tracked error;
  @tracked notice;
  @tracked period = "7";
  @tracked startDate = "";
  @tracked endDate = "";
  @tracked selectedUsers = [];
  @tracked userId = "";
  @tracked model = "";
  @tracked status = "";
  @tracked search = "";
  @tracked sort = "cost";
  @tracked completeness = "";
  @tracked errorCode = "";
  @tracked sessionId = "";
  @tracked requestId = "";
  @tracked reasonFilter = "";
  @tracked rejected = false;
  @tracked expiredOnly = false;
  @tracked page = 0;
  @tracked cursor = null;
  @tracked cursorStack = [];
  @tracked dailyAmount = "";
  @tracked bonusAmount = "0";
  @tracked changeReason = "";
  @tracked saving = false;
  @tracked revision = 0;
  modelOptions = [];
  requestRevision = 0;
  constructor() {
    super(...arguments);
    if (this.isSessions) {
      const query = new URLSearchParams(location.search);
      this.userId = query.get("user_id") || "";
      this.completeness = query.get("complete") || "";
      this.status = query.get("status") || "";
      this.reasonFilter = query.get("reason") || "";
      this.selectedUsers = query.get("username") ? [query.get("username")] : [];
      this.model = query.get("model") || "";
      this.startDate = query.get("start_date") || "";
      this.endDate = query.get("end_date") || "";
      if (this.startDate && this.endDate) this.period = "custom";
      this.rejected = query.get("rejected") === "true";
      this.expiredOnly = query.get("expired") === "true";
    }
    this.refresh();
    const timer = setInterval(() => {
      if (
        !document.hidden &&
        !this.loading &&
        !this.saving &&
        this.args.mode === "overview"
      )
        this.refresh(false);
    }, 30000);
    registerDestructor(this, () => {
      clearInterval(timer);
      this.requestRevision++;
    });
  }
  get isOverview() {
    return this.args.mode === "overview";
  }
  get isUsers() {
    return this.args.mode === "users";
  }
  get isUser() {
    return this.args.mode === "user";
  }
  get isSessions() {
    return this.args.mode === "sessions";
  }
  get isSession() {
    return this.args.mode === "session";
  }
  get hasCharts() {
    return this.isOverview || this.isUser;
  }
  get title() {
    return `xgoose.admin.${this.isUser ? "user_detail" : this.isSession ? "transcript" : this.args.mode}`;
  }
  get timezone() {
    return (
      this.currentUser?.user_option?.timezone ||
      Intl.DateTimeFormat().resolvedOptions().timeZone ||
      "UTC"
    );
  }
  get report() {
    return this.isUser ? this.data?.report : this.data;
  }
  get filterParams() {
    const end = moment.tz(this.timezone);
    const start = end.clone().subtract(Number(this.period) - 1, "days");
    return {
      timezone: this.timezone,
      start_date:
        this.period === "custom" ? this.startDate : start.format("YYYY-MM-DD"),
      end_date:
        this.period === "custom" ? this.endDate : end.format("YYYY-MM-DD"),
      user_id: this.isSessions ? this.userId || undefined : undefined,
      username: this.selectedUsers[0] || undefined,
      model: this.model || undefined,
      status: this.status || undefined,
    };
  }
  @action async refresh(block = true) {
    const generation = ++this.requestRevision;
    if (block) this.loading = true;
    this.error = null;
    try {
      let path = this.args.mode;
      if (this.isUser) path = `users/${this.args.id}`;
      if (this.isSession) path = `sessions/${this.args.id}`;
      if (this.isSessions && this.rejected) path = "rejections";
      const params = {
        ...this.filterParams,
        page: this.page,
        search: this.search || undefined,
        sort: this.sort,
        cursor: this.cursor || undefined,
        complete: this.completeness || undefined,
        error_code: this.errorCode || undefined,
        session_id: this.sessionId || undefined,
        request_id: this.requestId || undefined,
        reason: this.reasonFilter || undefined,
        expired: this.expiredOnly ? "true" : undefined,
      };
      const result = await ajax(`${ROOT}/${path}.json`, {
        data: this.isSession ? {} : params,
      });
      if (this.isDestroying || generation !== this.requestRevision) return;
      this.data = result;
      this.modelOptions = (this.report?.models || this.modelOptions).map(
        (name) => ({ name }),
      );
      if (this.isUser && block) {
        this.dailyAmount =
          result.quota.personal_limit_usd == null
            ? ""
            : String(result.quota.personal_limit_usd);
        this.bonusAmount = String(result.quota.bonus_usd);
      }
      this.revision++;
    } catch (error) {
      if (generation === this.requestRevision && !this.isDestroying)
        this.error =
          error.jqXHR?.responseJSON?.errors?.join(" ") || t("load_failed");
    } finally {
      if (generation === this.requestRevision && !this.isDestroying)
        this.loading = false;
    }
  }
  @action update(field, event) {
    this[field] = event.target.value;
  }
  @action selectUser(names) {
    this.selectedUsers = names.slice(-1);
    this.userId = "";
  }
  @action apply(event) {
    event?.preventDefault();
    this.page = 0;
    this.cursor = null;
    this.cursorStack = [];
    this.refresh();
  }
  @action next() {
    if (this.isUsers) this.page++;
    else {
      this.cursorStack = [...this.cursorStack, this.cursor];
      this.cursor = this.data.next_cursor;
    }
    this.refresh();
  }
  @action previous() {
    if (this.isUsers) this.page = Math.max(this.page - 1, 0);
    else {
      this.cursor = this.cursorStack.at(-1);
      this.cursorStack = this.cursorStack.slice(0, -1);
    }
    this.refresh();
  }
  get canPrevious() {
    return this.page > 0 || this.cursorStack.length > 0;
  }
  get canNext() {
    return this.data?.has_more || this.data?.next_cursor;
  }
  @action user(id) {
    this.router.transitionTo("adminPlugins.show.xgoose-user", id);
  }
  @action session(id) {
    this.router.transitionTo("adminPlugins.show.xgoose-session", id);
  }
  @action logs(kind, period) {
    const values = Object.fromEntries(
      Object.entries(this.filterParams).filter(([, value]) => value != null),
    );
    if (this.isUser) values.user_id = this.args.id;
    const query = new URLSearchParams(values);
    if (typeof period === "string") {
      query.set("start_date", period.slice(0, 10));
      query.set("end_date", period.slice(0, 10));
    }
    if (kind === "incomplete") query.set("complete", "false");
    if (kind === "quota") {
      query.set("rejected", "true");
      query.set("reason", "quota_exceeded");
    }
    if (kind === "upstream") query.set("status", "failed");
    if (kind === "expired") {
      query.set("status", "reserved");
      query.set("expired", "true");
    }
    if (kind === "cleanup") {
      location.assign(getURL("/sidekiq/scheduler"));
      return;
    }
    location.assign(`${getURL(ROOT)}/sessions?${query}`);
  }
  @action changeLogType(event) {
    this.rejected = event.target.value === "rejections";
    this.apply();
  }
  @action async saveBudget(kind) {
    if (this.saving) return;
    this.saving = true;
    this.error = null;
    this.notice = null;
    try {
      const amount = kind === "daily" ? this.dailyAmount : this.bonusAmount;
      await ajax(`${ROOT}/users/${this.args.id}/budget.json`, {
        type: "PUT",
        data: {
          operation_id: crypto.randomUUID(),
          kind,
          amount_usd: amount === "" ? null : amount,
          reason: this.changeReason,
        },
      });
      this.notice = t("saved");
      this.changeReason = "";
      await this.refresh();
    } catch (error) {
      this.error =
        error.jqXHR?.responseJSON?.errors?.join(" ") || t("save_failed");
    } finally {
      this.saving = false;
    }
  }
  @action async removeSession() {
    this.dialog.deleteConfirm({
      message: t("delete_confirm"),
      didConfirm: async () => {
        try {
          await ajax(`${ROOT}/sessions/${this.args.id}.json`, {
            type: "DELETE",
          });
          this.router.transitionTo("adminPlugins.show.xgoose-sessions");
        } catch {
          this.error = t("delete_failed");
        }
      },
    });
  }
  get exportJson() {
    return getURL(`${ROOT}/sessions/${this.args.id}.json`);
  }
  get exportText() {
    return getURL(`${ROOT}/sessions/${this.args.id}.txt`);
  }
  get metrics() {
    const s = this.report?.summary || {};
    return [
      ["cost", dollars(s.cost)],
      ["active_users", s.active_users || 0],
      ["calls", s.calls || 0],
      ["failure_rate", `${((s.failure_rate || 0) * 100).toFixed(1)}%`],
    ].map(([key, value]) => ({ label: t(key), value }));
  }
  get healthRows() {
    const h = this.report?.health;
    if (!h) return [];
    return [
      { label: t("concurrency"), value: `${h.active} / ${h.capacity}` },
      { label: t("reserved"), value: dollars(h.reserved_microusd) },
      {
        label: t("cleanup"),
        value: h.cleanup_at ? this.dateLabel(h.cleanup_at) : t("no_data"),
      },
    ];
  }
  get alerts() {
    const h = this.report?.health;
    if (!h) return [];
    return [
      [h.upstream_alert, "upstream", "alert_upstream"],
      [h.expired > 0, "expired", "alert_expired"],
      [h.cleanup_stale, "cleanup", "alert_cleanup"],
      [h.incomplete > 0, "incomplete", "alert_incomplete"],
      [h.quota_rejections > 0, "quota", "alert_quota"],
    ]
      .filter(([active]) => active)
      .map(([, kind, key]) => ({ kind, text: t(key) }));
  }
  get charts() {
    const series = this.report?.series || [];
    const groups = [
      [
        "cost_chart",
        [
          [
            "reported_cost",
            (r) => (Number(r.cost || 0) - Number(r.estimated_cost || 0)) / 1e6,
            "#7366c5",
          ],
          [
            "estimated_cost",
            (r) => Number(r.estimated_cost || 0) / 1e6,
            "#d19a42",
          ],
        ],
      ],
      [
        "tokens_chart",
        [
          [
            "uncached_input",
            (r) =>
              r.input_tokens == null
                ? null
                : r.input_tokens - (r.cache_tokens || 0),
            "#7366c5",
          ],
          ["cache_tokens", (r) => r.cache_tokens, "#3a9b90"],
          ["output_tokens", (r) => r.output_tokens, "#4c8ac7"],
        ],
      ],
      [
        "requests_chart",
        [
          ["completed", (r) => r.completed || 0, "#3a9b90"],
          ["failed", (r) => r.failed || 0, "#c65b63"],
          ["interrupted", (r) => r.interrupted || 0, "#d19a42"],
          ["rejected", (r) => r.rejected || 0, "#848b94"],
        ],
      ],
      [
        "latency_chart",
        [
          ["duration_p50", (r) => r.duration_p50, "#7366c5"],
          ["duration_p95", (r) => r.duration_p95, "#ad7bc4"],
          ["first_token_p50", (r) => r.first_token_p50, "#3a9b90"],
          ["first_token_p95", (r) => r.first_token_p95, "#4c8ac7"],
        ],
      ],
    ];
    const textColor = getComputedStyle(document.documentElement)
      .getPropertyValue("--primary")
      .trim();
    return groups.map(([key, fields]) => ({
      id: `${key}-${this.revision}`,
      title: t(key),
      config: {
        type: key === "latency_chart" ? "line" : "bar",
        data: {
          labels: series.map((r) =>
            r.period
              .replace("T", " ")
              .slice(0, this.report.bucket === "hour" ? 16 : 10),
          ),
          datasets: fields.map(([label, read, color]) => ({
            label: t(label),
            data: series.map(read),
            backgroundColor: color,
            borderColor: color,
            borderWidth: 1,
            tension: 0.2,
            spanGaps: false,
          })),
        },
        options: {
          color: textColor,
          responsive: true,
          maintainAspectRatio: false,
          animation: false,
          plugins: {
            legend: { position: "bottom", labels: { color: textColor } },
          },
          scales: {
            x: {
              stacked: key !== "latency_chart",
              ticks: { color: textColor },
            },
            y: { beginAtZero: true, stacked: key !== "latency_chart" },
          },
          onClick: (_event, elements) => {
            if (elements.length)
              this.logs("all", series[elements[0].index]?.period);
          },
        },
      },
      rows: series.map((r) => ({
        period: r.period,
        values: fields
          .map(([label, read]) => `${t(label)}: ${read(r) ?? t("no_data")}`)
          .join(" · "),
      })),
    }));
  }
  dateLabel(value) {
    return new Date(value).toLocaleString(undefined, {
      timeZone: this.timezone,
    });
  }
  get userRows() {
    return (this.data?.users || []).map((r) => ({
      ...r,
      costLabel: dollars(r.cost),
      usedLabel: dollars(r.today.used),
      reservedLabel: dollars(r.today.reserved),
      limitLabel: dollars(r.today.limit),
      remainingLabel: dollars(r.today.remaining),
      lastLabel: r.last_active ? this.dateLabel(r.last_active) : t("no_data"),
    }));
  }
  get topUsers() {
    return (this.report?.users || []).map((r) => ({
      ...r,
      costLabel: dollars(r.cost),
    }));
  }
  get sessionRows() {
    return (this.data?.sessions || []).map((r) => ({
      ...r,
      costLabel: dollars(r.cost),
      dateLabel: this.dateLabel(r.created_at),
      integrity: r.complete
        ? t("complete")
        : r.reasons.map((key) => t(`integrity.${key}`)).join(", "),
    }));
  }
  get rejectedRows() {
    return (this.data?.rejections || []).map((r) => ({
      ...r,
      dateLabel: this.dateLabel(r.created_at),
    }));
  }
  get quotaRows() {
    const q = this.data?.quota || {};
    return [
      ["daily_limit", q.base_limit_usd],
      ["today_bonus", q.bonus_usd],
      ["used", q.used_usd],
      ["reserved", q.reserved_usd],
      ["remaining", q.remaining_usd],
    ].map(([key, value]) => ({
      label: t(key),
      value: dollars(Number(value || 0) * 1e6),
    }));
  }
  get changes() {
    return (this.data?.changes || []).map((r) => ({
      ...r,
      dateLabel: this.dateLabel(r.created_at),
      beforeLabel: this.changeLabel(r.before_values),
      afterLabel: this.changeLabel(r.after_values),
    }));
  }
  changeLabel(v) {
    return `${t("daily_limit")}: ${v.daily_microusd == null ? t("site_default") : dollars(v.daily_microusd)}; ${t("today_bonus")}: ${dollars(v.bonus_microusd)}`;
  }
  get timeline() {
    return (this.data?.timeline || []).map((turn) => ({
      ...turn,
      costLabel: dollars(turn.charged_microusd),
      questionMessage: {
        role: "user",
        content: this.messageText(turn.question?.content),
      },
      steps: turn.steps.map((step) => ({
        ...step,
        purposeLabel: t(`purpose.${step.purpose}`),
        statusLabel: t(
          step.status === "reserved" ? "in_progress" : step.status,
        ),
        message: { role: "assistant", content: step.response.content || "" },
        tools: pretty(step.response.tool_calls),
        results: step.tool_results.map((r) => ({ payload: pretty(r.payload) })),
      })),
      eventsLabel: pretty(turn.client_events),
    }));
  }
  messageText(content) {
    if (typeof content === "string") return content;
    return (content || []).map((p) => p.text || t("image_metadata")).join("\n");
  }
  get rawRequests() {
    return (this.data?.requests || []).map((r) => ({
      id: r.request_id,
      status: r.status,
      cost: dollars(r.charged_microusd),
      body: pretty(r),
    }));
  }
  get integrityText() {
    return this.data?.complete
      ? t("complete")
      : this.data?.reasons?.map((key) => t(`integrity.${key}`)).join(", ");
  }

  <template>
    <section class="xgoose-admin">
      <DPageSubheader @titleLabel={{i18n this.title}} />
      {{#if this.error}}<div
          class="alert alert-error"
          role="alert"
        >{{this.error}}</div>{{/if}}
      {{#if this.notice}}<div
          class="alert alert-success"
          role="status"
        >{{this.notice}}</div>{{/if}}
      {{#unless this.isSession}}
        <form class="xgoose-admin-filters" {{on "submit" this.apply}}>
          <label>{{i18n "xgoose.admin.period"}}<select
              value={{this.period}}
              aria-label={{i18n "xgoose.admin.period"}}
              {{on "change" (fn this.update "period")}}
            >
              <option value="1" selected={{eq this.period "1"}}>{{i18n
                  "xgoose.admin.today"
                }}</option><option
                value="7"
                selected={{eq this.period "7"}}
              >{{i18n "xgoose.admin.days7"}}</option><option
                value="30"
                selected={{eq this.period "30"}}
              >{{i18n "xgoose.admin.days30"}}</option><option
                value="90"
                selected={{eq this.period "90"}}
              >{{i18n "xgoose.admin.days90"}}</option><option
                value="custom"
                selected={{eq this.period "custom"}}
              >{{i18n "xgoose.admin.custom"}}</option>
            </select></label>
          {{#if (eq this.period "custom")}}<label>{{i18n
                "xgoose.admin.from"
              }}<input
                type="date"
                value={{this.startDate}}
                {{on "change" (fn this.update "startDate")}}
              /></label><label>{{i18n "xgoose.admin.to"}}<input
                type="date"
                value={{this.endDate}}
                {{on "change" (fn this.update "endDate")}}
              /></label>{{/if}}
          {{#unless this.isUser}}{{#unless this.isUsers}}<div
                class="xgoose-admin-user-filter"
              ><span>{{i18n "xgoose.admin.user"}}</span><UserChooser
                  @value={{this.selectedUsers}}
                  @onChange={{this.selectUser}}
                  @options={{hash maximum=1}}
                /></div>{{/unless}}{{/unless}}
          {{#unless this.isUsers}}<label>{{i18n "xgoose.admin.model"}}<input
                value={{this.model}}
                list="xgoose-model-options"
                placeholder={{i18n "xgoose.admin.all_models"}}
                {{on "input" (fn this.update "model")}}
              /></label>
            <label>{{i18n "xgoose.admin.status"}}<select
                value={{this.status}}
                {{on "change" (fn this.update "status")}}
              ><option value="" selected={{eq this.status ""}}>{{i18n
                    "xgoose.admin.all"
                  }}</option><option value="completed">{{i18n
                    "xgoose.admin.completed"
                  }}</option><option value="failed">{{i18n
                    "xgoose.admin.failed"
                  }}</option><option value="interrupted">{{i18n
                    "xgoose.admin.interrupted"
                  }}</option><option value="reserved">{{i18n
                    "xgoose.admin.in_progress"
                  }}</option></select></label>{{/unless}}
          {{#if this.isUsers}}<label>{{i18n "xgoose.admin.username"}}<input
                value={{this.search}}
                {{on "input" (fn this.update "search")}}
              /></label><label>{{i18n "xgoose.admin.sort"}}<select
                value={{this.sort}}
                {{on "change" (fn this.update "sort")}}
              ><option value="cost" selected={{eq this.sort "cost"}}>{{i18n
                    "xgoose.admin.cost"
                  }}</option><option value="calls">{{i18n
                    "xgoose.admin.calls"
                  }}</option><option value="recent">{{i18n
                    "xgoose.admin.last_active"
                  }}</option></select></label>{{/if}}
          <DButton
            @type="submit"
            @label="xgoose.admin.apply"
            @disabled={{this.loading}}
          />
        </form>
        <datalist id="xgoose-model-options">{{#each
            this.modelOptions
            as |option|
          }}<option value={{option.name}} />{{/each}}</datalist>
        <p class="xgoose-admin-caption">{{this.timezone}}
          ·
          {{i18n "xgoose.admin.utc_reset"}}</p>
      {{/unless}}
      {{#if this.loading}}<p role="status">{{i18n
            "xgoose.admin.loading"
          }}</p>{{else}}
        {{#if this.hasCharts}}
          {{#if this.isUser}}
            <h2>{{this.data.user.username}}</h2>
            <dl class="xgoose-admin-stats">{{#each
                this.quotaRows
                as |stat|
              }}<div><dt>{{stat.label}}</dt><dd
                  >{{stat.value}}</dd></div>{{/each}}</dl>
            <details class="xgoose-admin-budget"><summary>{{i18n
                  "xgoose.admin.edit_budget"
                }}</summary>
              <p>{{i18n "xgoose.admin.budget_help"}}</p>
              <label>{{i18n "xgoose.admin.reason"}}<textarea
                  value={{this.changeReason}}
                  {{on "input" (fn this.update "changeReason")}}
                /></label>
              <div class="xgoose-admin-budget-fields"><label>{{i18n
                    "xgoose.admin.daily_limit"
                  }}<input
                    type="number"
                    min="0"
                    max="1000"
                    step="0.000001"
                    value={{this.dailyAmount}}
                    placeholder={{i18n "xgoose.admin.site_default"}}
                    {{on "input" (fn this.update "dailyAmount")}}
                  /></label><DButton
                  @label="xgoose.admin.save_daily"
                  @action={{fn this.saveBudget "daily"}}
                  @disabled={{this.saving}}
                /></div>
              <div class="xgoose-admin-budget-fields"><label>{{i18n
                    "xgoose.admin.today_bonus"
                  }}<input
                    type="number"
                    min="0"
                    max="1000"
                    step="0.000001"
                    value={{this.bonusAmount}}
                    {{on "input" (fn this.update "bonusAmount")}}
                  /></label><DButton
                  @label="xgoose.admin.save_bonus"
                  @action={{fn this.saveBudget "bonus"}}
                  @disabled={{this.saving}}
                /></div>
            </details>
          {{/if}}
          <dl class="xgoose-admin-stats">{{#each this.metrics as |stat|}}<div
              ><dt>{{stat.label}}</dt><dd
                >{{stat.value}}</dd></div>{{/each}}</dl>
          <p class="xgoose-admin-caption">{{i18n "xgoose.admin.cost_note"}}</p>
          {{#if this.isOverview}}
            <dl class="xgoose-admin-health">{{#each
                this.healthRows
                as |stat|
              }}<div><dt>{{stat.label}}</dt><dd
                  >{{stat.value}}</dd></div>{{/each}}</dl>
            {{#each this.alerts as |alert|}}<div
                class="alert alert-warning"
              ><button
                  class="btn-link"
                  type="button"
                  {{on "click" (fn this.logs alert.kind)}}
                >{{alert.text}}</button></div>{{/each}}
          {{/if}}
          <div class="xgoose-admin-charts">{{#each
              this.charts key="id"
              as |chart|
            }}<section><h3>{{chart.title}}</h3><Chart
                  @chartConfig={{chart.config}}
                /><details><summary>{{i18n
                      "xgoose.admin.chart_data"
                    }}</summary><table class="table"><tbody>{{#each
                        chart.rows
                        as |row|
                      }}<tr><th>{{row.period}}</th><td
                          >{{row.values}}</td></tr>{{else}}<tr><td>{{i18n
                              "xgoose.admin.empty"
                            }}</td></tr>{{/each}}</tbody></table></details></section>{{/each}}</div>
          <p>{{i18n "xgoose.admin.turns"}}:
            {{this.report.summary.turns}}
            ·
            {{i18n "xgoose.admin.tool_calls"}}:
            {{this.report.summary.tool_calls}}
            ·
            {{i18n "xgoose.admin.summaries"}}:
            {{this.report.summary.summaries}}
            ·
            {{i18n "xgoose.admin.rejected"}}:
            {{this.report.summary.rejected}}</p>
          {{#if this.isOverview}}<h3>{{i18n
                "xgoose.admin.top_users"
              }}</h3><table class="table xgoose-admin-table"><thead><tr><th
                  >{{i18n "xgoose.admin.user"}}</th><th>{{i18n
                      "xgoose.admin.cost"
                    }}</th><th>{{i18n
                      "xgoose.admin.calls"
                    }}</th></tr></thead><tbody>{{#each
                  this.topUsers
                  as |row|
                }}<tr><td><button
                        type="button"
                        class="btn-link"
                        {{on "click" (fn this.user row.id)}}
                      >{{row.username}}</button></td><td
                    >{{row.costLabel}}</td><td
                    >{{row.calls}}</td></tr>{{else}}<tr><td colspan="3">{{i18n
                        "xgoose.admin.empty"
                      }}</td></tr>{{/each}}</tbody></table>{{/if}}
          {{#if this.isUser}}
            <h3>{{i18n "xgoose.admin.sessions"}}</h3><table class="table"><tbody
              >{{#each this.data.recent_sessions as |row|}}<tr><td
                    >{{row.created_at}}</td><td><button
                        type="button"
                        class="btn-link"
                        {{on "click" (fn this.session row.id)}}
                      >#{{row.id}}</button></td></tr>{{else}}<tr><td>{{i18n
                        "xgoose.admin.empty"
                      }}</td></tr>{{/each}}</tbody></table>
            <DButton
              @label="xgoose.admin.all_sessions"
              @action={{fn this.logs "all"}}
            />
            <h3>{{i18n "xgoose.admin.recent_errors"}}</h3><table
              class="table"
            ><tbody>{{#each this.data.recent_errors as |row|}}<tr><td
                    >{{row.created_at}}</td><td>{{row.error_code}}</td><td
                    ><button
                        type="button"
                        class="btn-link"
                        {{on "click" (fn this.session row.session_id)}}
                      >#{{row.session_id}}</button></td></tr>{{else}}<tr><td
                    >{{i18n
                        "xgoose.admin.empty"
                      }}</td></tr>{{/each}}</tbody></table>
            <h3>{{i18n "xgoose.admin.rejected"}}</h3><table class="table"><tbody
              >{{#each this.data.rejections as |row|}}<tr><td
                    >{{row.created_at}}</td><td
                    >{{row.reason}}</td></tr>{{else}}<tr><td>{{i18n
                        "xgoose.admin.empty"
                      }}</td></tr>{{/each}}</tbody></table>
            <h3>{{i18n "xgoose.admin.changes"}}</h3><table class="table"><thead
              ><tr><th>{{i18n "xgoose.admin.date"}}</th><th>{{i18n
                      "xgoose.admin.admin"
                    }}</th><th>{{i18n "xgoose.admin.before"}}</th><th>{{i18n
                      "xgoose.admin.after"
                    }}</th><th>{{i18n
                      "xgoose.admin.reason"
                    }}</th></tr></thead><tbody>{{#each
                  this.changes
                  as |change|
                }}<tr><td>{{change.dateLabel}}<br />{{change.day}} UTC</td><td
                    >{{change.admin_username}}</td><td
                    >{{change.beforeLabel}}</td><td
                    >{{change.afterLabel}}</td><td
                    >{{change.reason}}</td></tr>{{else}}<tr><td
                      colspan="5"
                    >{{i18n
                        "xgoose.admin.empty"
                      }}</td></tr>{{/each}}</tbody></table>
          {{/if}}
        {{/if}}
        {{#if this.isUsers}}<div class="xgoose-admin-scroll"><table
              class="table xgoose-admin-table"
            ><thead><tr><th>{{i18n "xgoose.admin.user"}}</th><th>{{i18n
                      "xgoose.admin.cost"
                    }}</th><th>{{i18n "xgoose.admin.calls"}}</th><th>{{i18n
                      "xgoose.admin.tokens"
                    }}</th><th>{{i18n "xgoose.admin.used_today"}}</th><th>{{i18n
                      "xgoose.admin.reserved"
                    }}</th><th>{{i18n "xgoose.admin.daily_limit"}}</th><th
                  >{{i18n "xgoose.admin.remaining"}}</th><th>{{i18n
                      "xgoose.admin.failed"
                    }}</th><th>{{i18n
                      "xgoose.admin.last_active"
                    }}</th></tr></thead><tbody>{{#each
                  this.userRows
                  as |row|
                }}<tr><td><button
                        type="button"
                        class="btn-link"
                        {{on "click" (fn this.user row.id)}}
                      >{{row.username}}</button></td><td
                    >{{row.costLabel}}</td><td>{{row.calls}}</td><td
                    >{{row.tokens}}</td><td>{{row.usedLabel}}</td><td
                    >{{row.reservedLabel}}</td><td>{{row.limitLabel}}</td><td
                    >{{row.remainingLabel}}</td><td>{{row.failed}}</td><td
                    >{{row.lastLabel}}</td></tr>{{else}}<tr><td
                      colspan="10"
                    >{{i18n
                        "xgoose.admin.empty"
                      }}</td></tr>{{/each}}</tbody></table></div>{{/if}}
        {{#if this.isSessions}}
          <form class="xgoose-admin-filters" {{on "submit" this.apply}}>
            <label>{{i18n "xgoose.admin.log_type"}}<select
                value={{if this.rejected "rejections" "sessions"}}
                {{on "change" this.changeLogType}}
              ><option value="sessions" selected={{not this.rejected}}>{{i18n
                    "xgoose.admin.sessions"
                  }}</option><option
                  value="rejections"
                  selected={{this.rejected}}
                >{{i18n "xgoose.admin.rejected"}}</option></select></label>
            {{#unless this.rejected}}<label>{{i18n
                  "xgoose.admin.integrity_label"
                }}<select
                  value={{this.completeness}}
                  {{on "change" (fn this.update "completeness")}}
                ><option value="" selected={{eq this.completeness ""}}>{{i18n
                      "xgoose.admin.all"
                    }}</option><option value="true">{{i18n
                      "xgoose.admin.complete"
                    }}</option><option value="false">{{i18n
                      "xgoose.admin.incomplete"
                    }}</option></select></label><label>{{i18n
                  "xgoose.admin.session_id"
                }}<input
                  value={{this.sessionId}}
                  {{on "input" (fn this.update "sessionId")}}
                /></label><label>{{i18n "xgoose.admin.request_id"}}<input
                  value={{this.requestId}}
                  {{on "input" (fn this.update "requestId")}}
                /></label><label>{{i18n "xgoose.admin.error_code"}}<input
                  value={{this.errorCode}}
                  {{on "input" (fn this.update "errorCode")}}
                /></label>{{/unless}}
            <label>{{i18n "xgoose.admin.error_code"}}<input
                value={{this.reasonFilter}}
                {{on "input" (fn this.update "reasonFilter")}}
              /></label>
            <DButton @type="submit" @label="xgoose.admin.apply" />
          </form>
          <div class="xgoose-admin-scroll"><table
              class="table xgoose-admin-table"
            ><thead><tr><th>{{i18n "xgoose.admin.date"}}</th><th>{{i18n
                      "xgoose.admin.user"
                    }}</th><th>{{i18n "xgoose.admin.session_id"}}</th><th>{{i18n
                      "xgoose.admin.cost"
                    }}</th><th>{{i18n "xgoose.admin.calls"}}</th><th>{{i18n
                      "xgoose.admin.status"
                    }}</th></tr></thead><tbody>
                {{#if this.rejected}}{{#each this.rejectedRows as |row|}}<tr><td
                      >{{row.dateLabel}}</td><td><button
                          type="button"
                          class="btn-link"
                          {{on "click" (fn this.user row.user_id)}}
                        >{{row.username}}</button></td><td
                      >{{row.session_id}}</td><td>—</td><td>—</td><td
                      >{{row.reason}}</td></tr>{{else}}<tr><td
                        colspan="6"
                      >{{i18n "xgoose.admin.empty"}}</td></tr>{{/each}}
                {{else}}{{#each this.sessionRows as |row|}}<tr><td
                      >{{row.dateLabel}}</td><td><button
                          type="button"
                          class="btn-link"
                          {{on "click" (fn this.user row.user_id)}}
                        >{{row.username}}</button></td><td><button
                          type="button"
                          class="btn-link"
                          {{on "click" (fn this.session row.id)}}
                        >#{{row.id}}</button></td><td>{{row.costLabel}}</td><td
                      >{{row.calls}}</td><td
                      >{{row.integrity}}</td></tr>{{else}}<tr><td
                        colspan="6"
                      >{{i18n "xgoose.admin.empty"}}</td></tr>{{/each}}{{/if}}
              </tbody></table></div>
        {{/if}}
        {{#if this.isSession}}
          <p>#{{this.data.session.id}}
            ·
            {{i18n "xgoose.admin.user"}}
            #{{this.data.session.user_id}}
            ·
            {{this.integrityText}}</p>
          <p class="xgoose-admin-caption">{{i18n
              "xgoose.admin.client_note"
            }}</p>
          <div class="xgoose-admin-actions"><a
              class="btn"
              href={{this.exportJson}}
              download
            >JSON</a><a class="btn" href={{this.exportText}} download>{{i18n
                "xgoose.admin.export"
              }}</a><DButton
              @label="xgoose.admin.delete"
              @class="btn-danger"
              @action={{this.removeSession}}
            /></div>
          {{#each this.timeline as |turn|}}<section
              class="xgoose-admin-turn"
            ><h3>{{i18n "xgoose.admin.turn"}}
                {{turn.costLabel}}
                ·
                {{turn.tokens}}
                {{i18n "xgoose.admin.tokens"}}
                ·
                {{turn.duration_ms}}
                ms</h3><XgooseMessage @message={{turn.questionMessage}} />
              {{#each turn.steps as |step|}}<p
                  class="xgoose-admin-caption"
                >{{step.purposeLabel}} · {{step.statusLabel}}</p><XgooseMessage
                  @message={{step.message}}
                />
                {{#if step.response.tool_calls.length}}<details><summary>{{i18n
                        "xgoose.admin.tool_calls"
                      }}</summary><pre>{{step.tools}}</pre>{{#each
                      step.results
                      as |result|
                    }}<p>{{i18n "xgoose.admin.client_note"}}</p><pre
                      >{{result.payload}}</pre>{{/each}}</details>{{/if}}
              {{/each}}<details><summary>{{i18n
                    "xgoose.admin.client_events"
                  }}</summary><pre>{{turn.eventsLabel}}</pre></details>
            </section>{{/each}}
          <h3>{{i18n "xgoose.admin.raw_requests"}}</h3>{{#each
            this.rawRequests
            as |row|
          }}<details class="xgoose-admin-raw"><summary>{{row.id}}
                ·
                {{row.status}}
                ·
                {{row.cost}}</summary><pre>{{row.body}}</pre></details>{{/each}}
        {{/if}}
        {{#if this.isUsers}}<div class="xgoose-admin-actions"><DButton
              @label="xgoose.admin.previous"
              @action={{this.previous}}
              @disabled={{not this.canPrevious}}
            /><DButton
              @label="xgoose.admin.next"
              @action={{this.next}}
              @disabled={{not this.canNext}}
            /></div>{{/if}}
        {{#if this.isSessions}}<div class="xgoose-admin-actions"><DButton
              @label="xgoose.admin.previous"
              @action={{this.previous}}
              @disabled={{not this.canPrevious}}
            /><DButton
              @label="xgoose.admin.next"
              @action={{this.next}}
              @disabled={{not this.canNext}}
            /></div>{{/if}}
      {{/if}}
    </section>
  </template>
}
