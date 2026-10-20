# frozen_string_literal: true
module DiscourseXgoose
  class Metric < ActiveRecord::Base
    self.table_name = "xgoose_metrics"
    def self.capture!(request)
      usage = request.provider_usage
      input = usage["prompt_tokens"]
      cached = usage.dig("prompt_tokens_details", "cached_tokens")
      upsert(
        {
          request_id: request.id,
          session_id: request.session_id,
          user_id: request.user_id,
          turn_id: request.turn_id,
          model: request.model,
          status: request.status,
          purpose: request.purpose,
          charged_microusd: request.charged_microusd,
          charged_tokens: request.charged_tokens,
          estimated: request.estimated,
          input_tokens: input,
          output_tokens: usage["completion_tokens"],
          cache_tokens: cached && input ? cached.to_i.clamp(0, input) : nil,
          duration_ms: request.duration_ms,
          first_token_ms: request.first_token_ms,
          upstream_status: request.upstream_status,
          tool_calls: Array(request.response_message["tool_calls"]).compact.length,
          error_code: request.error_code,
          created_at: request.created_at,
        },
        unique_by: :request_id,
      )
    end
  end
end
