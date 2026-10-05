require 'test_helper'

class PasswordRecoveryTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'a recovery requires an email code and expiration' do
    recovery = PasswordRecovery.new
    assert_not recovery.valid?
    [:email, :recovery_code, :expires_at].each do |attribute|
      assert recovery.errors.added?(attribute, :blank)
    end
  end

  test 'creating a recovery normalizes email and sets a ten minute pending lifetime' do
    travel_to Time.zone.local(2026, 10, 5, 12) do
      recovery = PasswordRecovery.create_for_email('OWNER@EXAMPLE.COM')
      assert_equal 'owner@example.com', recovery.email
      assert_match(/\A[1-9]\d{5}\z/, recovery.recovery_code)
      assert_equal Time.zone.local(2026, 10, 5, 12, 10), recovery.expires_at
      assert_equal 0, recovery.attempts
      assert_not recovery.verified?
    end
  end

  test 'the matching code verifies the persisted recovery and records the attempt time' do
    travel_to Time.zone.local(2026, 10, 5, 12) do
      recovery = create_recovery
      result = recovery.verify_code('123456')
      assert result[:success]
      assert recovery.reload.verified?
      assert_equal 1, recovery.attempts
      assert_equal Time.current, recovery.last_attempt_at
    end
  end

  test 'a wrong code consumes one attempt without verifying' do
    recovery = create_recovery
    result = recovery.verify_code('000000')
    assert_not result[:success]
    assert_equal 1, recovery.reload.attempts
    assert_not recovery.verified?
    assert_match(/4/, result[:error])
  end

  test 'an expired recovery cannot be verified or consume an attempt' do
    recovery = create_recovery(expires_at: 1.second.ago, attempts: 2)
    assert_not recovery.verify_code('123456')[:success]
    assert_equal 2, recovery.reload.attempts
    assert_not recovery.verified?
  end

  test 'five incorrect attempts prevent a later correct code from verifying' do
    recovery = create_recovery
    5.times { assert_not recovery.verify_code('000000')[:success] }
    assert_not recovery.verify_code('123456')[:success]
    assert_equal 5, recovery.reload.attempts
    assert_not recovery.verified?
  end

  test 'the last allowed attempt can still verify a correct code' do
    recovery = create_recovery(attempts: 4)
    assert recovery.verify_code('123456')[:success]
    assert_equal 5, recovery.reload.attempts
    assert recovery.verified?
  end

  test 'cooldown is email specific case insensitive and expires after one minute' do
    travel_to Time.zone.local(2026, 10, 5, 12) do
      create_recovery(created_at: 30.seconds.ago)
      assert_not PasswordRecovery.can_request_new_code?('OWNER@EXAMPLE.COM')
      assert_equal 30, PasswordRecovery.cooldown_remaining('owner@example.com')
      assert PasswordRecovery.can_request_new_code?('other@example.com')
      travel 31.seconds
      assert PasswordRecovery.can_request_new_code?('owner@example.com')
      assert_equal 0, PasswordRecovery.cooldown_remaining('owner@example.com')
    end
  end

  test 'valid codes exclude verified and expired records' do
    pending = create_recovery
    verified = create_recovery(verified: true)
    expired = create_recovery(expires_at: 1.second.ago)
    ids = PasswordRecovery.valid_codes.pluck(:id)
    assert_includes ids, pending.id
    assert_not_includes ids, verified.id
    assert_not_includes ids, expired.id
  end

  test 'cleanup removes old recoveries while retaining recent ones' do
    old = create_recovery(created_at: 8.days.ago)
    recent = create_recovery(created_at: 6.days.ago)
    assert_equal 1, PasswordRecovery.cleanup_old_recoveries
    assert_not PasswordRecovery.exists?(old.id)
    assert PasswordRecovery.exists?(recent.id)
  end

  private

  def create_recovery(**attributes)
    PasswordRecovery.create!({
      email: 'owner@example.com', recovery_code: '123456',
      expires_at: 10.minutes.from_now, verified: false, attempts: 0
    }.merge(attributes))
  end
end
