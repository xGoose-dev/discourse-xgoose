# frozen_string_literal: true
require "json"
module DiscourseXgoose
  # Parses SSE independently of TCP chunk boundaries; stores a bounded partial
  # answer even when the browser disconnects or the upstream never sends DONE.
  class SseCollector
    attr_reader :message, :tokens, :done, :finish_reason, :usage, :meaningful_output
    def initialize
      @buffer = +""
      @event = []
      @message = { "role" => "assistant", "content" => +"", "tool_calls" => [] }
      @done = false
      @size = 0
    end
    def feed(chunk)
      @size += chunk.bytesize
      raise Error.new("upstream_too_large", 502) if @size > 2_097_152
      @buffer << chunk
      while (line = @buffer.slice!(/.*?\n/))
        line = line.sub(/\r?\n\z/, "")
        if line.empty?
          consume(@event.join("\n")) if @event.any?
          @event = []
        elsif line.start_with?("data:")
          @event << line.delete_prefix("data:").lstrip
        end
      end
    end
    def finish
      @event << @buffer.delete_prefix("data:").strip if @buffer.start_with?("data:")
      consume(@event.join("\n")) if @event.any?
      @buffer.clear
      @event = []
    end
    def consume(data)
      if data == "[DONE]"
        @done = true
        return
      end
      event = JSON.parse(data)
      raise Error.new("upstream_error", 502) if event["error"]
      usage = event["usage"]
      if usage.is_a?(Hash) && usage["prompt_tokens"].is_a?(Integer) &&
           usage["completion_tokens"].is_a?(Integer) && usage["prompt_tokens"] >= 0 &&
           usage["completion_tokens"] >= 0
        @tokens = usage["prompt_tokens"] + usage["completion_tokens"]
        @usage = usage
      end
      choice = event.fetch("choices", [])[0]
      return unless choice
      @finish_reason = choice["finish_reason"] if choice["finish_reason"]
      delta = choice["delta"] || {}
      @message["content"] << delta["content"] if delta["content"].is_a?(String)
      @meaningful_output ||= delta["content"].is_a?(String) && delta["content"].present?
      @meaningful_output ||=
        Array(delta["tool_calls"]).any? { |t| t.dig("function", "arguments").present? }
      Array(delta["tool_calls"]).each do |call|
        index = call["index"]
        raise Error.new("invalid_upstream", 502) unless index.is_a?(Integer) && index.between?(0, 7)
        item =
          @message["tool_calls"][index] ||= {
            "id" => +"",
            "type" => "function",
            "function" => {
              "name" => +"",
              "arguments" => +"",
            },
          }
        item["id"] << call["id"] if call["id"]
        %w[name arguments].each do |key|
          item["function"][key] << call.dig("function", key) if call.dig("function", key)
        end
      end
    rescue JSON::ParserError
      raise Error.new("invalid_upstream", 502)
    end
  end
end
