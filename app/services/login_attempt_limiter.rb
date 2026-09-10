require 'openssl'

# Counts every password-login request before password hashing. Shared across
# workers, expires automatically, and never changes a user's blocked flag.
class LoginAttemptLimiter
  RULES = [[30, 60], [10, 300], [100, 900]].freeze
  SCRIPT = <<~LUA.freeze
    local retry_after = 0
    for i, key in ipairs(KEYS) do
      local count = redis.call('INCR', key)
      local ttl = redis.call('TTL', key)
      if count == 1 or ttl < 0 then
        redis.call('EXPIRE', key, ARGV[i * 2])
        ttl = tonumber(ARGV[i * 2])
      end
      if count > tonumber(ARGV[i * 2 - 1]) then
        retry_after = math.max(retry_after, ttl, 1)
      end
    end
    return retry_after
  LUA

  def self.check(ip:, email:)
    new.check(ip: ip, email: email)
  end

  def initialize(redis: nil)
    @redis = redis
  end

  def check(ip:, email:)
    email = email.is_a?(String) ? email.strip.downcase : ''
    identities = [ip.to_s, [ip.to_s, email].to_json, email]
    keys = identities.each_with_index.map do |identity, index|
      digest = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, identity)
      "toppin:#{Rails.env}:login:v1:#{index}:#{digest}"
    end
    client = @redis || Redis.new(url: ENV.fetch('REDIS_URL'), connect_timeout: 0.3,
                                read_timeout: 0.3, write_timeout: 0.3, reconnect_attempts: 0)
    client.eval(SCRIPT, keys: keys, argv: RULES.flatten).to_i
  rescue Redis::BaseError
    # Availability policy: a Redis outage must not lock everyone out.
    # Deliberately omit connection URLs, emails, IPs and exception messages.
    Rails.logger.warn('[LoginAttemptLimiter] Redis unavailable; login throttling bypassed')
    0
  ensure
    client&.close unless @redis
  end
end
