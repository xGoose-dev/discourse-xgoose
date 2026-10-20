# frozen_string_literal: true
module DiscourseXgoose
  class Report
    attr_reader :metrics, :rejections, :from, :to, :timezone
    STAT_SQL = <<~SQL.squish.freeze
      COUNT(*) AS calls, COUNT(DISTINCT user_id) AS active_users,
      COUNT(DISTINCT (session_id, turn_id)) AS turns,
      COALESCE(SUM(charged_microusd),0) AS cost,
      COALESCE(SUM(charged_microusd) FILTER (WHERE estimated),0) AS estimated_cost,
      COALESCE(SUM(charged_tokens),0) AS tokens,
      SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens, SUM(cache_tokens) AS cache_tokens,
      COALESCE(SUM(tool_calls),0) AS tool_calls,
      COUNT(*) FILTER (WHERE status = 'completed') AS completed,
      COUNT(*) FILTER (WHERE status = 'failed') AS failed,
      COUNT(*) FILTER (WHERE status = 'interrupted') AS interrupted,
      COUNT(*) FILTER (WHERE purpose = 'summary') AS summaries,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms) AS duration_p50,
      percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) AS duration_p95,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY first_token_ms) AS first_token_p50,
      percentile_cont(0.95) WITHIN GROUP (ORDER BY first_token_ms) AS first_token_p95
    SQL
    def initialize(params)
      @params = params
      @timezone = params[:timezone].presence || "UTC"
      zone = ActiveSupport::TimeZone[@timezone]
      raise Discourse::InvalidParameters.new(:timezone) unless zone
      @timezone = zone.tzinfo.name
      @from =
        parse_date(params[:start_date], zone, false) ||
          6.days.ago.in_time_zone(zone).beginning_of_day
      @to = parse_date(params[:end_date], zone, true) || Time.current
      raise Discourse::InvalidParameters.new(:date_range) if @to < @from || @to - @from > 91.days
      @metrics = apply(Metric.all)
      @rejections = apply(Rejection.all, status: false)
    end
    def apply(scope, status: true)
      scope = scope.where(created_at: @from..@to)
      if @params[:username].present? && @params[:user_id].blank?
        scope = scope.where(user_id: User.find_by_username(@params[:username].to_s)&.id || -1)
      end
      if @params[:user_id].present?
        id = Integer(@params[:user_id].to_s, exception: false)
        raise Discourse::InvalidParameters.new(:user_id) unless id && id > 0 && id < 2**31
        scope = scope.where(user_id: id)
      end
      scope = scope.where(model: @params[:model].to_s.first(200)) if @params[:model].present?
      if status && @params[:status].present?
        unless %w[completed failed interrupted reserved].include?(@params[:status])
          raise Discourse::InvalidParameters.new(:status)
        end
        scope = scope.where(status: @params[:status])
      end
      scope
    end
    def stats(scope)
      scope
        .select(Arel.sql(STAT_SQL))
        .take
        .attributes
        .except("id")
        .transform_values { |v| v.is_a?(BigDecimal) ? v.to_f : v }
    end
    def overview
      bucket = @to - @from <= 2.days ? "hour" : "day"
      expression =
        Metric.sanitize_sql_array(
          ["date_trunc('#{bucket}', created_at AT TIME ZONE 'UTC' AT TIME ZONE ?)", @timezone],
        )
      series =
        @metrics
          .group(Arel.sql(expression))
          .order(Arel.sql(expression))
          .pluck(Arel.sql("#{expression} AS period"), Arel.sql("json_build_object(#{stat_json})"))
      denied = @rejections.group(Arel.sql(expression)).count
      points =
        series.map do |period, values|
          values.merge(
            "period" => period.strftime("%Y-%m-%dT%H:%M:%S"),
            "rejected" => denied.delete(period).to_i,
          )
        end
      denied.each do |period, count|
        points << { "period" => period.strftime("%Y-%m-%dT%H:%M:%S"), "rejected" => count }
      end
      # Keep zero-activity buckets visible; missing latency/usage stays unknown.
      by_period = points.index_by { |r| r["period"] }
      cursor = @from.in_time_zone(@timezone)
      cursor = bucket == "hour" ? cursor.beginning_of_hour : cursor.beginning_of_day
      points = []
      while cursor <= @to.in_time_zone(@timezone)
        label = cursor.strftime("%Y-%m-%dT%H:%M:%S")
        points << (
          by_period[label] ||
            {
              "period" => label,
              "cost" => 0,
              "estimated_cost" => 0,
              "completed" => 0,
              "failed" => 0,
              "interrupted" => 0,
              "rejected" => 0,
            }
        )
        cursor = bucket == "hour" ? cursor + 1.hour : cursor + 1.day
      end
      totals = stats(@metrics)
      terminal = totals["completed"].to_i + totals["failed"].to_i + totals["interrupted"].to_i
      totals["failure_rate"] = terminal.zero? ? 0 : totals["failed"].to_f / terminal
      totals["rejected"] = @rejections.count
      {
        summary: totals,
        series: points.sort_by { |r| r["period"] },
        bucket: bucket,
        users: users(limit: 10)[:users],
        health: health,
        models: Metric.distinct.order(:model).pluck(:model),
        range: {
          start: @from.iso8601,
          end: @to.iso8601,
          timezone: @timezone,
        },
        retention_days: SiteSetting.xgoose_log_retention_days,
      }
    end
    def users(limit: 50)
      ids =
        "#{@metrics.select(:user_id).to_sql} UNION #{@rejections.select(:user_id).to_sql} UNION #{Budget.select(:user_id).to_sql}"
      scope = User.where("users.id IN (#{ids})")
      if @params[:search].present?
        scope =
          User.where(
            "username_lower LIKE ?",
            "%#{User.sanitize_sql_like(@params[:search].to_s.downcase.first(100))}%",
          )
      end
      aggregation =
        @metrics.group(:user_id).select(
          :user_id,
          Arel.sql(
            "SUM(charged_microusd) AS cost, COUNT(*) AS calls, COUNT(*) FILTER (WHERE status = 'failed') AS failed, MAX(created_at) AS last_active, SUM(charged_tokens) AS tokens",
          ),
        )
      sort =
        {
          "cost" => "COALESCE(m.cost,0) DESC",
          "calls" => "COALESCE(m.calls,0) DESC",
          "recent" => "m.last_active DESC NULLS LAST",
        }[
          @params[:sort].to_s.presence || "cost"
        ]
      raise Discourse::InvalidParameters.new(:sort) unless sort
      scope = scope.joins("LEFT JOIN (#{aggregation.to_sql}) m ON m.user_id = users.id")
      count = scope.count
      page = Integer(@params[:page].to_s.presence || "0", exception: false)
      raise Discourse::InvalidParameters.new(:page) unless page && page.between?(0, 100_000)
      rows =
        scope
          .select(
            "users.id, users.username, users.uploaded_avatar_id, m.cost, m.calls, m.failed, m.last_active, m.tokens",
          )
          .order(Arel.sql("#{sort}, users.id"))
          .limit(limit)
          .offset(page * limit)
          .to_a
      budgets = Budget.where(user_id: rows.map(&:id)).index_by(&:user_id)
      usage = Usage.where(user_id: rows.map(&:id), day: Time.now.utc.to_date).index_by(&:user_id)
      {
        users:
          rows.map do |user|
            row, budget = usage[user.id], budgets[user.id]
            base = budget&.daily_microusd || Pricing.limit
            used, reserved, bonus =
              row&.used_microusd.to_i,
              row&.reserved_microusd.to_i,
              row&.bonus_microusd.to_i
            {
              id: user.id,
              username: user.username,
              avatar_template: User.avatar_template(user.username, user.uploaded_avatar_id),
              cost: user[:cost].to_i,
              calls: user[:calls].to_i,
              failed: user[:failed].to_i,
              tokens: user[:tokens].to_i,
              last_active: user[:last_active],
              today: {
                used: used,
                reserved: reserved,
                base: base,
                bonus: bonus,
                limit: base + bonus,
                remaining: [base + bonus - used - reserved, 0].max,
              },
            }
          end,
        page: page,
        has_more: (page + 1) * limit < count,
        total: count,
      }
    end
    def health
      now = Time.current
      recent = Metric.where(created_at: 15.minutes.ago..now).where.not(status: "reserved")
      total, failed = recent.count, recent.where(status: "failed").count
      expired = Request.where(status: "reserved").where("expires_at < ?", now).count
      cleanup = PluginStore.get("discourse-xgoose", "cleanup_at")
      stale = cleanup.nil? || Time.iso8601(cleanup) < 15.minutes.ago
      sessions = Session.where(id: @metrics.select(:session_id))
      incomplete = sessions.where(complete: false).count
      quota = @rejections.where(reason: "quota_exceeded").count
      {
        active: Discourse.redis.zcount("xgoose:active", Time.now.to_i, "+inf"),
        capacity: SiteSetting.xgoose_site_concurrency,
        reserved_microusd: Usage.where(day: Time.now.utc.to_date).sum(:reserved_microusd),
        expired: expired,
        cleanup_at: cleanup,
        cleanup_stale: stale,
        upstream_alert: total >= 5 && failed.to_f / total >= 0.2,
        recent_calls: total,
        recent_failed: failed,
        incomplete: incomplete,
        quota_rejections: quota,
      }
    end

    private

    def stat_json
      # Reuse precisely the same aggregate definitions for totals and chart buckets.
      STAT_SQL
        .split(/,\s*(?![^()]*\))/)
        .map do |fragment|
          value, key = fragment.strip.split(/ AS /i)
          "'#{key}', #{value}"
        end
        .join(", ")
    end
    def parse_date(value, zone, ending)
      return if value.blank?
      unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        raise Discourse::InvalidParameters.new(:date)
      end
      date = Date.iso8601(value.to_s)
      time = zone.local(date.year, date.month, date.day)
      ending ? time.end_of_day : time
    rescue ArgumentError
      raise Discourse::InvalidParameters.new(:date)
    end
  end
end
