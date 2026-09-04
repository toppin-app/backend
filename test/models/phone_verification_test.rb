require 'test_helper'

class PhoneVerificationTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    PhoneVerification.delete_all
  end

  test 'requires a phone number, code and expiration' do
    verification = PhoneVerification.new

    assert_not verification.valid?
    assert verification.errors.added?(:phone_number, :blank)
    assert verification.errors.added?(:verification_code, :blank)
    assert verification.errors.added?(:expires_at, :blank)
  end

  test 'generates a six digit code' do
    code = PhoneVerification.generate_code

    assert_match(/\A\d{6}\z/, code)
  end

  test 'creates a pending verification with the expected lifetime' do
    travel_to Time.zone.local(2026, 9, 4, 12, 0, 0) do
      verification = PhoneVerification.create_for_phone('+34612345678')

      assert_not verification.verified?
      assert_equal 0, verification.attempts
      assert_in_delta 10.minutes.from_now, verification.expires_at, 1.second
    end
  end

  test 'accepts the matching code and records the attempt' do
    verification = create_verification(code: '123456')

    result = verification.verify_code('123456')

    assert result[:success]
    assert verification.reload.verified?
    assert_equal 1, verification.attempts
    assert_not_nil verification.last_attempt_at
  end

  test 'rejects a wrong code and reports the remaining attempts' do
    verification = create_verification(code: '123456')

    result = verification.verify_code('000000')

    assert_not result[:success]
    assert_match(/4/, result[:error])
    assert_equal 1, verification.reload.attempts
    assert_not verification.verified?
  end

  test 'does not accept an expired code or consume another attempt' do
    verification = create_verification(expires_at: 1.second.ago, attempts: 2)

    result = verification.verify_code(verification.verification_code)

    assert_not result[:success]
    assert_equal 2, verification.reload.attempts
  end

  test 'blocks verification after the maximum number of attempts' do
    verification = create_verification(attempts: PhoneVerification::MAX_ATTEMPTS)

    result = verification.verify_code(verification.verification_code)

    assert_not result[:success]
    assert_equal PhoneVerification::MAX_ATTEMPTS, verification.reload.attempts
    assert_not verification.verified?
  end

  test 'enforces request cooldown and reports its remaining duration' do
    travel_to Time.zone.local(2026, 9, 4, 12, 0, 0) do
      create_verification(created_at: 30.seconds.ago)

      assert_not PhoneVerification.can_request_new_code?('+34612345678')
      assert_in_delta 30, PhoneVerification.cooldown_remaining('+34612345678'), 1

      travel 31.seconds
      assert PhoneVerification.can_request_new_code?('+34612345678')
      assert_equal 0, PhoneVerification.cooldown_remaining('+34612345678')
    end
  end

  test 'removes only verifications older than the retention period' do
    old_verification = create_verification(created_at: 8.days.ago)
    recent_verification = create_verification(
      phone: '+34600000001',
      created_at: 6.days.ago
    )

    assert_equal 1, PhoneVerification.cleanup_old_verifications
    assert_not PhoneVerification.exists?(old_verification.id)
    assert PhoneVerification.exists?(recent_verification.id)
  end

  private

  def create_verification(
    phone: '+34612345678',
    code: '123456',
    expires_at: 10.minutes.from_now,
    attempts: 0,
    created_at: Time.current
  )
    PhoneVerification.create!(
      phone_number: phone,
      verification_code: code,
      expires_at: expires_at,
      verified: false,
      attempts: attempts,
      created_at: created_at,
      updated_at: created_at
    )
  end
end
