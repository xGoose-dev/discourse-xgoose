# frozen_string_literal: true
module DiscourseXgoose
  # Use Discourse's multisite-aware pool and Rack socket takeover, as the core
  # streaming endpoints do. A slow provider must not hold a forum web worker.
  class StreamResponse
    def self.pool
      @pool ||= Scheduler::ThreadPool.new(min_threads: 0, max_threads: 32, idle_time: 30)
    end

    def self.queue(io, audit, body, lease)
      pool.post do
        begin
          io.write "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nTransfer-Encoding: chunked\r\nCache-Control: no-cache, no-store\r\nConnection: close\r\nX-Accel-Buffering: no\r\nX-Content-Type-Options: nosniff\r\n\r\n"
          io.flush
          Gateway.stream(audit, body) do |chunk|
            io.write "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
            io.flush
          end
          io.write "0\r\n\r\n"
          io.flush
          io.done if io.respond_to?(:done)
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          Quota.settle!(audit, tokens: 0, status: "interrupted", error: "connection_closed")
        ensure
          lease.release!
          io.close unless io.closed?
        end
      end
    rescue StandardError
      lease.release!
      Quota.settle!(audit, tokens: 0, status: "failed", error: "stream_unavailable")
      io.close unless io.closed?
      raise
    end
  end
end
