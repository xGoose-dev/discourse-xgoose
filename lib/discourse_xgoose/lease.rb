# frozen_string_literal: true
module DiscourseXgoose
  class Lease
    ACQUIRE = <<~LUA
      local now = tonumber(ARGV[1])
      redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
      redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', now)
      if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[4]) or redis.call('ZCARD', KEYS[2]) >= 1 then return 0 end
      redis.call('ZADD', KEYS[1], ARGV[2], ARGV[3])
      redis.call('ZADD', KEYS[2], ARGV[2], ARGV[3])
      redis.call('EXPIRE', KEYS[1], ARGV[5])
      redis.call('EXPIRE', KEYS[2], ARGV[5])
      return 1
    LUA
    def initialize(user, id)
      @id = id
      @keys = ["xgoose:active", "xgoose:active:#{user.id}"]
    end
    def acquire!
      ttl = SiteSetting.xgoose_timeout_seconds + 90
      now = Time.now.to_i
      result =
        Discourse.redis.eval(
          ACQUIRE,
          keys: @keys.map { |key| Discourse.redis.namespace_key(key) },
          argv: [now, now + ttl, @id, SiteSetting.xgoose_site_concurrency, ttl],
        )
      raise Error.new("busy", 429) unless result == 1
      @acquired = true
    end
    def release!
      @keys.each { |key| Discourse.redis.zrem(key, @id) } if @acquired
    end
  end
end
