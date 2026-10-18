# frozen_string_literal: true
require "net/http"
require "uri"
require "timeout"
module DiscourseXgoose
  class Gateway
    def self.configured?
      SiteSetting.xgoose_api_base_url.present? && SiteSetting.xgoose_api_key.present? &&
        SiteSetting.xgoose_model.present?
    end
    def self.endpoint
      uri = URI.parse(SiteSetting.xgoose_api_base_url.sub(%r{/+\z}, "") + "/chat/completions")
      unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && !uri.query &&
               !uri.fragment
        raise Error.new("invalid_configuration", 503)
      end
      uri
    rescue URI::InvalidURIError
      raise Error.new("invalid_configuration", 503)
    end
    def self.stream(request, body)
      collector = SseCollector.new
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = "failed"
      error = "upstream_error"
      begin
        uri = endpoint
        http = Net::HTTP.new(uri.host, uri.port, nil) # Do not inherit process HTTP_PROXY.
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = SiteSetting.xgoose_timeout_seconds
        upstream = Net::HTTP::Post.new(uri.request_uri)
        upstream["Authorization"] = "Bearer #{SiteSetting.xgoose_api_key}"
        upstream["Content-Type"] = "application/json"
        upstream["Accept"] = "text/event-stream"
        upstream.body = JSON.generate(body)
        Timeout.timeout(SiteSetting.xgoose_timeout_seconds) do
          http.start do |connection|
            connection.request(upstream) do |response|
              raise Error.new("upstream_http_#{response.code}", 502) unless response.code == "200"
              response.read_body do |chunk|
                collector.feed(chunk)
                yield chunk
              end
            end
          end
        end
        collector.finish
        raise Error.new("upstream_incomplete", 502) unless collector.done && collector.finish_reason
        status = "completed"
        error = nil
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        status = "interrupted"
        error = "connection_closed"
      rescue StandardError => e
        error =
          (
            if e.is_a?(Error)
              e.code
            else
              (e.is_a?(Timeout::Error) ? "upstream_timeout" : "upstream_error")
            end
          )
        begin
          yield "data: #{JSON.generate(error: { message: error, type: "xgoose_error" })}\n\n"
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          status = "interrupted"
        end
      ensure
        Quota.settle!(
          request,
          usage: (status == "completed" ? collector.usage : nil),
          response: collector.message.merge("finish_reason" => collector.finish_reason),
          status: status,
          error: error,
          duration: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
        )
      end
    end
  end
end
