require 'test_helper'
require 'minitest/mock'

class LoginAttemptLimiterTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    # Dedicated test Redis only. Never clear shared/application Redis data.
    @redis = Redis.new(url: ENV.fetch('LOGIN_LIMITER_TEST_REDIS_URL'))
    @namespace = SecureRandom.hex(12)
    @ip = "test-#{@namespace}"
    @email = "#{@namespace}@example.com"
    @limiter = LoginAttemptLimiter.new(redis: @redis)
    @keys = []
  end

  teardown do
    @redis.del(*@keys) if @keys.any?
    @redis.close
  end

  test 'ten attempts per account and IP then temporary rejection' do
    10.times { assert_equal 0, check }
    assert_includes 1..300, check
    assert @keys.all? { |key| @redis.ttl(key).positive? }
    assert @keys.none? { |key| key.include?(@email) || key.include?(@ip) }
  end

  test 'normalizes email and does not extend the waiting window' do
    10.times { check }
    @keys.each { |key| @redis.expire(key, 20) }
    assert_includes 1..20, check(email: "  #{@email.upcase}  ")
  end

  test 'IP limit applies even when the attacker rotates accounts' do
    30.times { |i| assert_equal 0, check(email: "#{i}-#{@email}") }
    assert_includes 1..60, check(email: "new-#{@email}")
  end

  test 'account limit applies across different IPs' do
    100.times { |i| assert_equal 0, check(ip: "#{@ip}-#{i}") }
    assert_includes 1..900, check(ip: "#{@ip}-next")
  end

  test 'unrelated users and IPs are unaffected' do
    11.times { check }
    assert_equal 0, check(ip: "#{@ip}-other", email: "other-#{@email}")
  end

  test 'expiry permits requests again' do
    11.times { check }
    @redis.del(*@keys)
    assert_equal 0, check
  end

  test 'concurrent requests cannot exceed the account and IP budget' do
    results = 20.times.map { Thread.new { check } }.map(&:value)
    assert_equal 10, results.count(0)
    assert_equal 10, results.count(&:positive?)
  end

  test 'Redis outage preserves availability without logging secrets' do
    broken = Object.new
    def broken.eval(*)
      raise Redis::CannotConnectError, 'redis://secret@example.com'
    end
    messages = []
    Rails.logger.stub(:warn, ->(message) { messages << message }) do
      assert_equal 0, LoginAttemptLimiter.new(redis: broken).check(ip: @ip, email: @email)
    end
    assert_equal ['[LoginAttemptLimiter] Redis unavailable; login throttling bypassed'], messages
  end

  private

  def check(ip: @ip, email: @email)
    # Capture only this test's hashed keys for cleanup, including concurrent calls.
    proxy = Object.new
    redis, keys = @redis, @keys
    proxy.define_singleton_method(:eval) do |script, **options|
      keys.concat(options[:keys])
      redis.eval(script, **options)
    end
    LoginAttemptLimiter.new(redis: proxy).check(ip: ip, email: email)
  end
end
