require 'test_helper'
require_relative '../support/t03_boundary_helpers'

class PasswordRecoveriesControllerTest < ActionDispatch::IntegrationTest
  include T03BoundaryHelpers
  self.fixture_table_names = []

  setup do
    @owner = create_boundary_user(name: 'Recovery Owner')
    @original_locale = I18n.locale
  end

  teardown do
    I18n.locale = @original_locale
  end

  test 'request rejects absent and malformed email without creating a recovery' do
    without_mail_delivery do
      [nil, 'invalid-address'].each do |email|
        assert_no_difference('PasswordRecovery.count') do
          post '/password_recoveries/request_code', params: { email: email }, as: :json
        end
        assert_response :bad_request
      end
    end
  end

  test 'request rejects unknown and soft deleted accounts' do
    @owner.update!(deleted_account: true)
    without_mail_delivery do
      ['missing@example.com', @owner.email].each do |email|
        assert_no_difference('PasswordRecovery.count') do
          post '/password_recoveries/request_code', params: { email: email }, as: :json
        end
        assert_response :not_found
        assert_equal 'USER_NOT_FOUND', response.parsed_body['code']
      end
    end
  end

  test 'anonymous request persists a pending code and sends that code to the owner' do
    with_mail_boundary do
      assert_difference('PasswordRecovery.count', 1) do
        post '/password_recoveries/request_code', params: {
          email: @owner.email.upcase, language: 'en'
        }, as: :json
      end
    end
    assert_response :ok
    assert_equal 600, response.parsed_body['expires_in']
    recovery = PasswordRecovery.find_by!(email: @owner.email)
    assert_not recovery.verified?
    assert_equal @owner.email.upcase, @sent_message.fetch('To').first.fetch('Email')
    assert_includes @sent_message.fetch('TextPart'), recovery.recovery_code
    assert_includes @sent_message.fetch('HTMLPart'), recovery.recovery_code
    assert_not response.parsed_body.key?('recovery_code')
  end

  test 'resend cooldown rejects another request without contacting the mail provider' do
    create_recovery
    without_mail_delivery do
      assert_no_difference('PasswordRecovery.count') do
        post '/password_recoveries/request_code', params: { email: @owner.email }, as: :json
      end
    end
    assert_response :too_many_requests
  end

  test 'a new code can be requested once the resend cooldown has elapsed' do
    create_recovery(created_at: 61.seconds.ago)
    with_mail_boundary do
      assert_difference('PasswordRecovery.count', 1) do
        post '/password_recoveries/request_code', params: { email: @owner.email }, as: :json
      end
    end
    assert_response :ok
  end

  # Characterizes the current failure path: the pending row survives a failed
  # send, and the owner remains subject to cooldown despite receiving no email.
  test 'mail provider failure returns 500 while retaining the pending recovery' do
    with_mail_boundary(failure: IOError.new('synthetic mail outage')) do
      assert_difference('PasswordRecovery.count', 1) do
        post '/password_recoveries/request_code', params: { email: @owner.email }, as: :json
      end
    end
    assert_response :internal_server_error
    recovery = PasswordRecovery.find_by!(email: @owner.email)
    assert_not recovery.verified?
    assert_equal 0, recovery.attempts
    assert_not PasswordRecovery.can_request_new_code?(@owner.email)
    assert @owner.reload.valid_password?('Original123!')
  end

  test 'verification requires both email and code' do
    post '/password_recoveries/verify_code', params: { email: @owner.email }, as: :json
    assert_response :bad_request
  end

  test 'verification cannot use a recovery for another email' do
    recovery = create_recovery
    post '/password_recoveries/verify_code', params: {
      email: 'someone-else@example.com', code: '123456'
    }, as: :json
    assert_response :not_found
    assert_not recovery.reload.verified?
    assert_equal 0, recovery.attempts
  end

  test 'a wrong code records a failed attempt without verifying the recovery' do
    recovery = create_recovery
    post '/password_recoveries/verify_code', params: {
      email: @owner.email, code: '000000'
    }, as: :json
    assert_response :bad_request
    assert_equal false, response.parsed_body['verified']
    assert_equal 1, recovery.reload.attempts
    assert_not recovery.verified?
  end

  test 'the latest pending code verifies while an older code is rejected' do
    older = create_recovery(recovery_code: '111111', created_at: 2.minutes.ago)
    latest = create_recovery(recovery_code: '222222')
    post '/password_recoveries/verify_code', params: {
      email: @owner.email, code: '111111'
    }, as: :json
    assert_response :bad_request
    assert_equal 1, latest.reload.attempts
    assert_equal 0, older.reload.attempts

    post '/password_recoveries/verify_code', params: {
      email: @owner.email.upcase, code: '222222'
    }, as: :json
    assert_response :ok
    assert_equal true, response.parsed_body['verified']
    assert latest.reload.verified?
    assert_not older.reload.verified?
  end

  test 'expired and exhausted codes cannot verify or consume another attempt' do
    [{ expires_at: 1.second.ago, attempts: 2 }, { attempts: 5 }].each do |attributes|
      recovery = create_recovery(**attributes)
      post '/password_recoveries/verify_code', params: {
        email: @owner.email, code: '123456'
      }, as: :json
      assert_response :bad_request
      assert_not recovery.reload.verified?
      assert_equal attributes[:attempts], recovery.attempts
      recovery.destroy!
    end
  end

  test 'reset requires an email and a new password' do
    post '/password_recoveries/reset_password', params: { email: @owner.email }, as: :json
    assert_response :bad_request
    assert @owner.reload.valid_password?('Original123!')
  end

  test 'recovery translation stays within its request instead of changing later requests' do
    I18n.with_locale(:en) do
      post '/password_recoveries/reset_password', params: { email: @owner.email, language: 'ES' }, as: :json
      assert_response :bad_request
      assert_equal :en, I18n.locale
    end
  end

  test 'unverified and expired recoveries cannot change the password' do
    [{ verified: false }, { verified: true, expires_at: 1.second.ago }].each do |attributes|
      recovery = create_recovery(**attributes)
      reset_password
      assert_response :forbidden
      assert_equal 'NOT_VERIFIED', response.parsed_body['code']
      assert @owner.reload.valid_password?('Original123!')
      assert PasswordRecovery.exists?(recovery.id)
      recovery.destroy!
    end
  end

  test 'reset cannot use a verified recovery for a different email' do
    create_recovery(email: 'different@example.com', verified: true)
    reset_password
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
  end

  test 'reset refuses an account deleted after its code was verified' do
    recovery = create_recovery(verified: true)
    @owner.update!(deleted_account: true)
    reset_password
    assert_response :not_found
    assert @owner.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)
  end

  test 'weak passwords preserve the existing password and verified recovery' do
    recovery = create_recovery(verified: true)
    reset_password(password: 'weak')
    assert_response :bad_request
    assert @owner.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)
  end

  test 'an anonymous client cannot reset using only another clients verified email' do
    recovery = create_recovery
    verifier = open_session
    verifier.post '/password_recoveries/verify_code', params: {
      email: @owner.email, code: '123456'
    }, as: :json
    assert_equal 200, verifier.response.status

    reset_password(code: nil)
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)

    reset_password(password: 'Another123!', code: nil)
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
  end

  test 'another authenticated account cannot reset the verified owner email without a proof' do
    recovery = create_recovery(verified: true)
    other = create_boundary_user
    reset_password(headers: authorization_for(other), code: nil)
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
    assert other.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)
  end

  test 'a verified legacy code can reset once and is then consumed' do
    recovery = create_recovery(verified: true)
    reset_password
    assert_response :ok
    assert @owner.reload.valid_password?('Replacement123!')
    assert_not PasswordRecovery.exists?(recovery.id)
    reset_password(password: 'Another123!')
    assert_response :forbidden
    assert @owner.reload.valid_password?('Replacement123!')
  end

  test 'a wrong legacy code cannot use a verified recovery' do
    recovery = create_recovery(verified: true)
    reset_password(code: '000000')
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)
  end

  test 'verification returns a private token whose digest alone is persisted and reset consumes it' do
    recovery = create_recovery
    post '/password_recoveries/verify_code', params: { email: @owner.email, code: '123456' }, as: :json
    assert_response :ok
    token = response.parsed_body['recovery_token']
    assert token.present?, 'verification must return a private reset proof'
    assert_operator token.length, :>=, 43
    assert_not_equal '123456', token
    assert_equal Digest::SHA256.hexdigest(token), recovery.reload.reset_token_digest
    assert_not_includes recovery.attributes.values, token
    reset_password(code: nil, recovery_token: token)
    assert_response :ok
    assert @owner.reload.valid_password?('Replacement123!')
    reset_password(password: 'Another123!', code: nil, recovery_token: token)
    assert_response :forbidden
    assert @owner.reload.valid_password?('Replacement123!')
  end

  test 'an invalid token never falls back to a supplied correct legacy code' do
    recovery = create_recovery(verified: true)
    reset_password(recovery_token: 'invalid-private-proof')
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)
  end

  test 'a private token from another email cannot reset this account' do
    create_recovery(verified: true, reset_token_digest: Digest::SHA256.hexdigest('owner-private-proof'))
    other = create_boundary_user
    create_recovery(email: other.email, verified: true, reset_token_digest: Digest::SHA256.hexdigest('other-private-proof'))
    reset_password(code: nil, recovery_token: 'other-private-proof')
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
    assert other.reload.valid_password?('Original123!')
  end

  test 'five failed reset proofs prevent a later correct code without reusing verification attempts' do
    recovery = create_recovery(verified: true, attempts: 5)
    5.times do
      reset_password(code: '000000')
      assert_response :forbidden
    end
    reset_password
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
    assert_equal 5, recovery.reload.reset_attempts
    assert_equal 5, recovery.attempts
  end

  test 'the fifth valid verification attempt still allows the legacy reset' do
    create_recovery(attempts: 4)
    post '/password_recoveries/verify_code', params: { email: @owner.email, code: '123456' }, as: :json
    assert_response :ok
    reset_password
    assert_response :ok
    assert @owner.reload.valid_password?('Replacement123!')
  end

  test 'requesting a newer recovery invalidates an earlier verified code' do
    create_recovery(verified: true, created_at: 2.minutes.ago)
    with_mail_boundary do
      post '/password_recoveries/request_code', params: { email: @owner.email }, as: :json
    end
    assert_response :ok
    reset_password
    assert_response :forbidden
    assert @owner.reload.valid_password?('Original123!')
  end

  test 'a successful reset consumes every outstanding recovery for the account' do
    create_recovery(verified: true, created_at: 2.minutes.ago, recovery_code: '222222')
    create_recovery(verified: true)
    reset_password
    assert_response :ok
    assert_equal 0, PasswordRecovery.for_email(@owner.email).count
  end

  test 'missing proof cannot exhaust a verified recovery reset budget' do
    recovery = create_recovery(verified: true)
    6.times do
      reset_password(code: nil)
      assert_response :forbidden
    end
    assert_equal 0, recovery.reload.reset_attempts
    reset_password
    assert_response :ok
  end

  test 'a failure consuming a recovery rolls back the password change as well' do
    recovery = create_recovery(verified: true)
    owner_email = @owner.email
    recovery_class = PasswordRecovery
    original_callbacks = recovery_class._destroy_callbacks.dup
    failure = ->(record) { raise 'synthetic recovery deletion failure' if record.email == owner_email }
    recovery_class.set_callback(:destroy, :before, failure)
    reset_password
    assert_response :internal_server_error
    assert @owner.reload.valid_password?('Original123!')
    assert PasswordRecovery.exists?(recovery.id)
  ensure
    recovery_class._destroy_callbacks = original_callbacks if original_callbacks
  end

  test 'malformed email and password values fail without changing credentials' do
    create_recovery(verified: true)
    [[], 123, { nested: 'value' }].each do |email|
      post '/password_recoveries/request_code', params: { email: email }, as: :json
      assert_response :bad_request
      post '/password_recoveries/verify_code', params: { email: email, code: '123456' }, as: :json
      assert_response :bad_request
      post '/password_recoveries/reset_password', params: { email: email, code: '123456', new_password: 'Replacement123!' }, as: :json
      assert_response :bad_request
    end
    post '/password_recoveries/reset_password', params: { email: @owner.email, code: '123456', new_password: ['Replacement123!'] }, as: :json
    assert_response :bad_request
    assert @owner.reload.valid_password?('Original123!')
  end

  private

  def create_recovery(**attributes)
    PasswordRecovery.create!({
      email: @owner.email, recovery_code: '123456',
      expires_at: 10.minutes.from_now, verified: false, attempts: 0
    }.merge(attributes))
  end

  def reset_password(password: 'Replacement123!', headers: {}, code: '123456', recovery_token: nil)
    post '/password_recoveries/reset_password', params: {
      email: @owner.email, new_password: password, code: code, recovery_token: recovery_token
    }, headers: headers, as: :json
  end

  def with_mail_boundary(failure: nil)
    sender = lambda do |messages:|
      raise failure if failure
      @sent_message = messages.fetch(0)
      # The controller consumes only the SDK call's completion, not its body.
      Object.new
    end
    Mailjet::Send.stub(:create, sender) { yield }
  end

  def without_mail_delivery
    Mailjet::Send.stub(:create, ->(*) { flunk 'Rejected request reached mail provider' }) { yield }
  end
end
