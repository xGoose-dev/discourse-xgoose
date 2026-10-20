# frozen_string_literal: true
module DiscourseXgoose
  class Quota
    def self.snapshot(user)
      row = Usage.find_by(user_id: user.id, day: Time.now.utc.to_date)
      used, reserved = row&.used_microusd.to_i, row&.reserved_microusd.to_i
      {
        limit_usd: limit_for(user, row) / 1_000_000.0,
        base_limit_usd: base_limit(user) / 1_000_000.0,
        bonus_usd: row&.bonus_microusd.to_i / 1_000_000.0,
        personal_limit_usd: Budget.find_by(user_id: user.id)&.daily_microusd&./(1_000_000.0),
        used_usd: used / 1_000_000.0,
        reserved_usd: reserved / 1_000_000.0,
        remaining_usd: [limit_for(user, row) - used - reserved, 0].max / 1_000_000.0,
        used: row&.used.to_i,
        reserved: row&.reserved.to_i,
        resets_at: (Time.now.utc.to_date + 1).to_time(:utc).iso8601,
      }
    end
    def self.reserve!(user, session, request_id, turn_id, body, amount)
      day = Time.now.utc.to_date
      rates = Pricing.rates
      dollars = Pricing.reserve(amount, rates)
      budget = Budget.ensure_for!(user)
      Usage.transaction do
        budget.lock!
        usage = ensure_usage!(user, day)
        usage.lock!
        if usage.used_microusd + usage.reserved_microusd + dollars >
             (budget.daily_microusd || Pricing.limit) + usage.bonus_microusd
          raise Error.new("quota_exceeded", 429)
        end
        session.lock!
        if session.requests.where(turn_id: turn_id).count >= SiteSetting.xgoose_max_turn_calls
          raise Error.new("turn_limit", 429)
        end
        request =
          session.requests.create!(
            user_id: user.id,
            request_id: request_id,
            turn_id: turn_id,
            model: body[:model],
            purpose: body.delete(:xgoose_purpose) || "unknown",
            messages: Payload.audit_messages(body[:messages]),
            reserved_tokens: amount,
            reserved_microusd: dollars,
            pricing_rates: rates,
            usage_date: day,
            expires_at: Time.now.utc + SiteSetting.xgoose_timeout_seconds + 90,
          )
        usage.update!(
          reserved: usage.reserved + amount,
          reserved_microusd: usage.reserved_microusd + dollars,
        )
        Metric.capture!(request)
        session.touch
        session.update!(complete: false, integrity_reasons: ["request_in_progress"])
        request
      end
    rescue ActiveRecord::RecordNotUnique
      raise Error.new("duplicate_request", 409)
    end
    def self.settle!(
      request,
      tokens: nil,
      usage: nil,
      response: {},
      status: "completed",
      error: nil,
      duration: nil,
      first_token_ms: nil,
      upstream_status: nil
    )
      Usage.transaction do
        ledger = Usage.lock.find_by!(user_id: request.user_id, day: request.usage_date)
        request.lock!
        return unless request.status == "reserved"
        actual = usage.is_a?(Hash) || (tokens.is_a?(Integer) && tokens >= 0)
        usage ||= { "prompt_tokens" => tokens, "completion_tokens" => 0 } if actual
        charged =
          (
            if actual
              usage["prompt_tokens"].to_i + usage["completion_tokens"].to_i
            else
              request.reserved_tokens
            end
          )
        dollars =
          (
            if actual
              Pricing.cost(usage, request.pricing_rates.presence || Pricing.rates)
            else
              request.reserved_microusd
            end
          )
        ledger.update!(
          reserved: [ledger.reserved - request.reserved_tokens, 0].max,
          used: ledger.used + charged,
          reserved_microusd: [ledger.reserved_microusd - request.reserved_microusd, 0].max,
          used_microusd: ledger.used_microusd + dollars,
        )
        request.update!(
          charged_tokens: charged,
          charged_microusd: dollars,
          estimated: !actual,
          provider_usage: usage || {},
          response_message: response,
          status: status,
          error_code: error,
          duration_ms: duration,
          first_token_ms: first_token_ms,
          upstream_status: upstream_status,
        )
        Metric.capture!(request)
        Transcript.refresh!(request.session)
      end
    end
    def self.ensure_usage!(user, day)
      Usage.insert_all(
        [{ user_id: user.id, day: day, used: 0, reserved: 0 }],
        unique_by: %i[user_id day],
      )
      Usage.find_by!(user_id: user.id, day: day)
    end
    def self.base_limit(user)
      Budget.find_by(user_id: user.id)&.daily_microusd || Pricing.limit
    end
    def self.limit_for(user, usage = nil)
      usage ||= Usage.find_by(user_id: user.id, day: Time.now.utc.to_date)
      base_limit(user) + usage&.bonus_microusd.to_i
    end
    def self.reap!
      Request
        .where(status: "reserved")
        .where("expires_at < ?", Time.now.utc)
        .find_each { |request| settle!(request, status: "interrupted", error: "lease_expired") }
    end
  end
end
