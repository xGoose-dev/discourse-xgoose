# frozen_string_literal: true
module DiscourseXgoose
  class SessionsController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login
    before_action :check_access
    before_action :load_session, only: %i[completion events]
    rescue_from DiscourseXgoose::Error do |error|
      record_rejection(error.code)
      render json: {
               error: error.code,
               message:
                 I18n.t("xgoose.errors.#{error.code}", default: I18n.t("xgoose.errors.generic")),
             },
             status: error.status
    end

    rescue_from RateLimiter::LimitExceeded do |_error|
      record_rejection("rate_limited")
      render json: {
               error: "rate_limited",
               message: I18n.t("xgoose.errors.rate_limited"),
             },
             status: 429
    end

    def configuration
      render json: {
               configured: Gateway.configured?,
               model: SiteSetting.xgoose_model,
               context_tokens: SiteSetting.xgoose_context_tokens,
               max_output_tokens: SiteSetting.xgoose_max_output_tokens,
               max_turn_calls: SiteSetting.xgoose_max_turn_calls,
               system_prompt: Payload::SYSTEM,
               pricing: Pricing.rates,
               quota: Quota.snapshot(current_user),
               session_cost_usd:
                 Request.where(user_id: current_user.id, session_id: params[:session_id].to_i).sum(
                   :charged_microusd,
                 ) / 1_000_000.0,
             }
    end
    def create
      RateLimiter.new(current_user, "xgoose-session", 10, 60, apply_limit_to_staff: true).performed!
      render json: { id: Session.create!(user_id: current_user.id).id }, status: :created
    end
    def completion
      raise Error.new("not_configured", 503) unless Gateway.configured?
      Gateway.endpoint
      raise Error.new("request_too_large", 413) if request.raw_post.bytesize > 6_291_456
      request_id = request.headers["X-Xgoose-Request-Id"]
      turn_id = request.headers["X-Xgoose-Turn-Id"]
      unless Payload::UUID.match?(request_id.to_s) && Payload::UUID.match?(turn_id.to_s)
        raise Error.new("invalid_id")
      end
      body, amount = Payload.build(params.to_unsafe_h)
      purpose = request.headers["X-Xgoose-Purpose"].to_s
      raise Error.new("invalid_purpose") unless ["", "generation", "summary"].include?(purpose)
      body[:xgoose_purpose] = purpose.presence || "unknown"
      RateLimiter.new(
        current_user,
        "xgoose-model",
        SiteSetting.xgoose_requests_per_minute,
        60,
        apply_limit_to_staff: true,
      ).performed!
      Quota.reap!
      lease = Lease.new(current_user, request_id)
      lease.acquire!
      begin
        audit = Quota.reserve!(current_user, @session, request_id, turn_id, body, amount)
        if request.env["rack.hijack"]
          request.env["discourse.request_tracker.skip"] = true
          io = request.env["rack.hijack"].call
          StreamResponse.queue(io, audit, body, lease)
          transferred = true
          render plain: "", status: 418
        else
          # Rack test adapters do not expose a socket. Buffer only in that case.
          output = +""
          Gateway.stream(audit, body) { |chunk| output << chunk }
          render body: output, content_type: "text/event-stream"
        end
      ensure
        lease.release! unless transferred
      end
    end
    def events
      raise Error.new("request_too_large", 413) if request.raw_post.bytesize > 131_072
      RateLimiter.new(current_user, "xgoose-events", 120, 60, apply_limit_to_staff: true).performed!
      items = params[:events]
      raise Error.new("invalid_events") unless items.is_a?(Array) && items.length.between?(1, 20)
      raise Error.new("event_limit", 429) if @session.events.count + items.length > 2000
      rows =
        items.map do |item|
          value = item.to_unsafe_h
          unless Payload::UUID.match?(value["event_id"].to_s) &&
                   Payload::UUID.match?(value["turn_id"].to_s) &&
                   value["sequence"].is_a?(Integer) && value["sequence"] >= 0 &&
                   %w[tool_start tool_end turn_end aborted compaction].include?(value["kind"]) &&
                   value["payload"].is_a?(Hash)
            raise Error.new("invalid_events")
          end
          {
            session_id: @session.id,
            event_id: value["event_id"],
            turn_id: value["turn_id"],
            sequence: value["sequence"],
            kind: value["kind"],
            payload: value["payload"],
            created_at: Time.now.utc,
          }
        end
      @session.with_lock do
        Event.insert_all(rows, unique_by: %i[session_id event_id])
        Transcript.refresh!(@session)
      end
      render json: { ok: true }
    end

    private

    def record_rejection(code)
      unless action_name == "completion" && current_user && @session &&
               @session.user_id == current_user.id
        return
      end
      return if @session.requests.exists?(request_id: request.headers["X-Xgoose-Request-Id"].to_s)
      Rejection.create!(
        user_id: current_user.id,
        session_id: @session.id,
        reason: code,
        model: SiteSetting.xgoose_model,
        created_at: Time.current,
      )
    end
    def check_access
      if !SiteSetting.xgoose_enabled || current_user.suspended? || !current_user.active?
        raise Discourse::InvalidAccess
      end
      # CSRF remains enabled. Same-origin is an additional browser boundary,
      # not an authentication substitute. Origin is mandatory for mutations.
      if !request.get?
        origin = request.headers["Origin"]
        raise Discourse::InvalidAccess unless origin == Discourse.base_url
      end
    end
    def load_session
      @session = Session.find_by(id: params[:id], user_id: current_user.id)
      raise Discourse::NotFound unless @session
    end
  end
end
