require 'test_helper'

class PhoneVerificationsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    PhoneVerification.delete_all
    User.delete_all
  end

  test 'request_code requires a phone number' do
    post '/phone_verifications/request_code', params: {}, as: :json

    assert_response :bad_request
    assert_equal 400, response.parsed_body['status']
  end

  test 'request_code rejects malformed international numbers' do
    post '/phone_verifications/request_code', params: {
      phone_number: '612345678', language: 'it'
    }, as: :json

    assert_response :bad_request
    assert_equal 0, PhoneVerification.count
  end

  test 'request_code refuses a phone assigned to an active account' do
    create_user(phone: '+34612345678')

    post '/phone_verifications/request_code', params: {
      phone_number: '+34612345678', language: 'es'
    }, as: :json

    assert_response :conflict
    assert_equal 'PHONE_ALREADY_EXISTS', response.parsed_body['code']
    assert_equal 0, PhoneVerification.count
  end

  test 'request_code creates a pending code and returns expiry metadata' do
    assert_difference('PhoneVerification.count', 1) do
      post '/phone_verifications/request_code', params: {
        phone_number: '+34612345678', language: 'it'
      }, as: :json
    end

    assert_response :success
    body = response.parsed_body
    assert_equal 200, body['status']
    assert_equal '+34612345678', body['phone_number']
    assert_equal PhoneVerification::CODE_EXPIRATION_TIME.to_i, body['expires_in']
    assert_not PhoneVerification.last.verified?
  end

  test 'request_code enforces the resend cooldown' do
    PhoneVerification.create_for_phone('+34612345678')

    assert_no_difference('PhoneVerification.count') do
      post '/phone_verifications/request_code', params: {
        phone_number: '+34612345678'
      }, as: :json
    end

    assert_response :too_many_requests
  end

  test 'verify_code requires both phone and code' do
    post '/phone_verifications/verify_code', params: {
      phone_number: '+34612345678'
    }, as: :json

    assert_response :bad_request
  end

  test 'verify_code reports when there is no pending verification' do
    post '/phone_verifications/verify_code', params: {
      phone_number: '+34612345678', code: '123456'
    }, as: :json

    assert_response :not_found
  end

  test 'verify_code records a failed attempt without verifying the phone' do
    verification = create_verification(code: '123456')

    post '/phone_verifications/verify_code', params: {
      phone_number: verification.phone_number,
      code: '000000',
      language: 'en'
    }, as: :json

    assert_response :bad_request
    assert_equal false, response.parsed_body['verified']
    assert_equal 1, verification.reload.attempts
    assert_not verification.verified?
  end

  test 'verify_code marks the pending verification as verified' do
    verification = create_verification(code: '123456')

    post '/phone_verifications/verify_code', params: {
      phone_number: verification.phone_number,
      code: '123456',
      language: 'de'
    }, as: :json

    assert_response :success
    assert_equal true, response.parsed_body['verified']
    assert verification.reload.verified?
  end

  test 'verify_code refuses a phone assigned since the code was requested' do
    verification = create_verification
    create_user(phone: verification.phone_number)

    post '/phone_verifications/verify_code', params: {
      phone_number: verification.phone_number,
      code: verification.verification_code
    }, as: :json

    assert_response :conflict
    assert_not verification.reload.verified?
  end

  private

  def create_verification(code: '123456')
    PhoneVerification.create!(
      phone_number: '+34612345678',
      verification_code: code,
      expires_at: 10.minutes.from_now,
      verified: false,
      attempts: 0
    )
  end

  def create_user(phone:)
    User.create!(
      email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'Secure123!',
      password_confirmation: 'Secure123!',
      phone: phone
    )
  end
end
