# frozen_string_literal: true
module DiscourseXgoose
  class Quota
    def self.snapshot(user)
      row = Usage.find_by(user_id: user.id, day: Time.now.utc.to_date)
      {
        limit: SiteSetting.xgoose_daily_tokens,
        used: row&.used.to_i,
        reserved: row&.reserved.to_i,
        remaining: [SiteSetting.xgoose_daily_tokens - row&.used.to_i - row&.reserved.to_i, 0].max,
        resets_at: (Time.now.utc.to_date + 1).to_time(:utc).iso8601,
      }
    end

    def self.reserve!(user, session, request_id, turn_id, body, amount)
      day = Time.now.utc.to_date
      # Unique index also handles the first request in two concurrent processes.
      Usage.insert_all(
        [{ user_id: user.id, day: day, used: 0, reserved: 0 }],
        unique_by: %i[user_id day],
      )
      Usage.transaction do
        usage = Usage.lock.find_by!(user_id: user.id, day: day)
        if usage.used + usage.reserved + amount > SiteSetting.xgoose_daily_tokens
          raise Error.new("quota_exceeded", 429)
        end
        if session.requests.where(turn_id: turn_id).count >= SiteSetting.xgoose_max_turn_calls
          raise Error.new("turn_limit", 429)
        end
        request =
          session.requests.create!(
            user_id: user.id,
            request_id: request_id,
            turn_id: turn_id,
            model: body[:model],
            messages: body[:messages],
            reserved_tokens: amount,
            usage_date: day,
            expires_at: Time.now.utc + SiteSetting.xgoose_timeout_seconds + 90,
          )
        usage.update!(reserved: usage.reserved + amount)
        request
      end
    rescue ActiveRecord::RecordNotUnique
      raise Error.new("duplicate_request", 409)
    end

    def self.settle!(
      request,
      tokens: nil,
      response: {},
      status: "completed",
      error: nil,
      duration: nil
    )
      # Consistent lock ordering with reserve: usage before request.
      Usage.transaction do
        usage = Usage.lock.find_by!(user_id: request.user_id, day: request.usage_date)
        request.lock!
        return unless request.status == "reserved"
        actual = tokens.is_a?(Integer) && tokens >= 0
        charged = actual ? tokens : request.reserved_tokens
        usage.update!(
          reserved: [usage.reserved - request.reserved_tokens, 0].max,
          used: usage.used + charged,
        )
        request.update!(
          charged_tokens: charged,
          estimated: !actual,
          response_message: response,
          status: status,
          error_code: error,
          duration_ms: duration,
        )
      end
    end

    def self.reap!
      Request
        .where(status: "reserved")
        .where("expires_at < ?", Time.now.utc)
        .find_each { |request| settle!(request, status: "interrupted", error: "lease_expired") }
    end
  end
end
