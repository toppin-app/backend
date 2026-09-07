require 'test_helper'
require 'minitest/mock'

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @password = 'Secure123!'
    @user = User.create!(
      email: 'email-login@example.com',
      password: @password,
      password_confirmation: @password,
      name: 'Email Login User'
    )
  end

  test 'email login returns the user and an authorization token' do
    twilio_calls = []

    post_login_with_twilio_stubbed(
      email: @user.email,
      password: @password,
      calls: twilio_calls
    )

    assert_response :success
    assert_equal @user.id, response.parsed_body['id']
    assert_equal @user.email, response.parsed_body['email']
    assert_not response.parsed_body.key?('encrypted_password')
    assert_not_includes response.body, @password
    assert_match(/^Bearer /, response.headers['Authorization'])
    assert_equal [@user.id], twilio_calls
    assert_equal 1, @user.reload.sign_in_count
  end

  test 'email login does not recreate the Twilio identity when it already exists' do
    @user.update!(twilio_sid: 'twilio-user-sid')
    twilio_calls = []

    post_login_with_twilio_stubbed(
      email: @user.email,
      password: @password,
      calls: twilio_calls
    )

    assert_response :success
    assert_empty twilio_calls
  end

  test 'email login rejects a wrong password without issuing a token' do
    assert_no_login_side_effects do
      post '/login.json', params: login_params(@user.email, 'Wrong123!'), as: :json
    end

    assert_response :bad_request
    assert_equal invalid_credentials_response, response.parsed_body
    assert_nil response.headers['Authorization']
  end

  test 'email login rejects an unknown address with the same public response' do
    assert_no_login_side_effects do
      post '/login.json', params: login_params('unknown@example.com', @password), as: :json
    end

    assert_response :bad_request
    assert_equal invalid_credentials_response, response.parsed_body
    assert_nil response.headers['Authorization']
  end

  test 'email login rejects a blocked account and returns its reason key' do
    @user.update!(blocked: true, block_reason_key: 'harassment')
    twilio_calls = []

    post_login_with_twilio_stubbed(
      email: @user.email,
      password: @password,
      calls: twilio_calls
    )

    assert_response :forbidden
    assert_equal(
      {
        'error' => 'Usuario bloqueado',
        'blocked' => true,
        'status' => 403,
        'block_reason_key' => 'harassment'
      },
      response.parsed_body
    )
    assert_nil response.headers['Authorization']
    assert_empty twilio_calls
    assert_equal 0, @user.reload.sign_in_count
  end

  test 'email login omits an absent block reason without exposing internal data' do
    @user.update!(blocked: true, block_reason_key: nil)

    post_login_with_twilio_stubbed(email: @user.email, password: @password)

    assert_response :forbidden
    assert_equal true, response.parsed_body['blocked']
    assert_not response.parsed_body.key?('block_reason_key')
    assert_nil response.headers['Authorization']
  end

  test 'email login refuses a soft-deleted account without issuing a token' do
    @user.update!(deleted_account: true)
    twilio_calls = []

    post_login_with_twilio_stubbed(
      email: @user.email,
      password: @password,
      calls: twilio_calls
    )

    assert_response :unauthorized
    assert_nil response.headers['Authorization']
    assert_empty twilio_calls
    assert_equal 0, @user.reload.sign_in_count
  end

  test 'email login requires the user envelope' do
    assert_raises(ActionController::ParameterMissing) do
      post '/login.json', params: { email: @user.email, password: @password }, as: :json
    end
  end

  private

  def login_params(email, password)
    { user: { email: email, password: password } }
  end

  def invalid_credentials_response
    {
      'error' => 'No such user; check the submitted email address',
      'status' => 400
    }
  end

  def post_login_with_twilio_stubbed(email:, password:, calls: [])
    twilio = Object.new
    twilio.define_singleton_method(:generate_user_in_twilio) do |user_id|
      calls << user_id
      true
    end

    TwilioController.stub(:new, twilio) do
      post '/login.json', params: login_params(email, password), as: :json
    end
  end

  def assert_no_login_side_effects
    twilio = Object.new
    twilio.define_singleton_method(:generate_user_in_twilio) do |_user_id|
      flunk 'Twilio must not be called for rejected credentials'
    end

    TwilioController.stub(:new, twilio) do
      yield
    end

    assert_equal 0, @user.reload.sign_in_count
  end
end
