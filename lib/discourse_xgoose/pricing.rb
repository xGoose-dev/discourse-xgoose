# frozen_string_literal: true
require "bigdecimal"
module DiscourseXgoose
  class Pricing
    def self.rates
      {
        "input" => SiteSetting.xgoose_input_usd_per_million.to_s,
        "output" => SiteSetting.xgoose_output_usd_per_million.to_s,
        "cache_read" => SiteSetting.xgoose_cached_usd_per_million.to_s,
        "cache_write" => SiteSetting.xgoose_cache_write_usd_per_million.to_s,
      }
    end
    def self.limit
      (BigDecimal(SiteSetting.xgoose_daily_budget_usd.to_s) * 1_000_000).floor
    end
    def self.reserve(token_bound, rates)
      (BigDecimal(rates.values.map { |v| BigDecimal(v) }.max.to_s) * token_bound).ceil
    end
    def self.cost(usage, rates)
      input = usage.fetch("prompt_tokens", 0).to_i
      output = usage.fetch("completion_tokens", 0).to_i
      cached = [usage.dig("prompt_tokens_details", "cached_tokens").to_i, input].min.clamp(0, input)
      written = [
        usage.dig("prompt_tokens_details", "cache_write_tokens").to_i,
        input - cached,
      ].min.clamp(0, input - cached)
      # USD per million tokens * tokens is exactly micro-USD. Round up once.
      (
        (input - cached - written) * BigDecimal(rates.fetch("input")) +
          cached * BigDecimal(rates.fetch("cache_read")) +
          written * BigDecimal(rates.fetch("cache_write")) +
          output * BigDecimal(rates.fetch("output"))
      ).ceil
    end
  end
end
