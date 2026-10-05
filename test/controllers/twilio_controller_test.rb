require 'test_helper'
require 'ostruct'
require_relative '../support/t03_boundary_helpers'

class TwilioControllerTest < ActionDispatch::IntegrationTest
  include T03BoundaryHelpers
  self.fixture_table_names = []

  setup do
    @user = create_boundary_user
  end

  test 'anonymous callers cannot obtain a chat access token' do
    without_provider_calls { get '/generate_access_token', as: :json }
    assert_response :unauthorized
  end

  test 'expired invalid and revoked JWTs cannot obtain a chat access token' do
    [authorization_for(@user, exp: 1.second.ago.to_i),
     { 'Authorization' => 'Bearer invalid-jwt' },
     authorization_for(@user, jti: 'revoked-test-jti')].each do |headers|
      without_provider_calls { get '/generate_access_token', headers: headers, as: :json }
      assert_response :unauthorized
    end
  end

  test 'blocked callers cannot obtain a chat access token' do
    @user.update!(blocked: true)
    without_provider_calls do
      get '/generate_access_token', headers: authorization_for(@user), as: :json
    end
    assert_response :unauthorized
    assert_equal true, response.parsed_body['blocked']
  end

  test 'an authenticated caller receives a token for its own chat identity' do
    with_twilio_boundary do
      get '/generate_access_token', headers: authorization_for(@user), as: :json
    end
    assert_response :ok
    # The current action renders a raw JWT string with JSON content type.
    assert_equal 'test-chat-access-token', response.body
    assert_equal @user.id, @issued_identity
    assert_equal 'IS-test-service', @issued_service
  end

  test 'another account cannot request a token for the owner through user_id' do
    other = create_boundary_user
    with_twilio_boundary do
      get '/generate_access_token', params: { user_id: @user.id },
          headers: authorization_for(other), as: :json
    end
    assert_response :ok
    assert_equal other.id, @issued_identity
  end

  test 'admin receives a token for its own account' do
    admin = create_boundary_user(admin: true)
    with_twilio_boundary do
      get '/generate_access_token', headers: authorization_for(admin), as: :json
    end
    assert_response :ok
    assert_equal admin.id, @issued_identity
  end

  # Current reliability boundary: this action has no provider-error handler.
  test 'a Twilio configuration failure propagates without issuing an access token' do
    with_twilio_boundary(failure: IOError.new('synthetic provider outage')) do
      error = assert_raises(IOError) do
        get '/generate_access_token', headers: authorization_for(@user), as: :json
      end
      assert_equal 'synthetic provider outage', error.message
    end
    assert_nil @issued_identity
  end

  private

  def without_provider_calls
    Twilio::REST::Client.stub(:new, ->(*) { flunk 'Unauthorized request reached Twilio' }) { yield }
  end

  def with_twilio_boundary(failure: nil)
    configuration = Object.new
    configuration.define_singleton_method(:update) do |reachability_enabled:|
      raise failure if failure
      raise 'Reachability contract changed' unless reachability_enabled
      true
    end
    service = OpenStruct.new(configuration: configuration)
    v1 = Object.new
    v1.define_singleton_method(:services) do |sid|
      raise 'Wrong chat service' unless sid == 'IS-test-service'
      service
    end
    client = OpenStruct.new(conversations: OpenStruct.new(v1: v1))
    issuer = lambda do |account_sid, api_key, api_secret, grants, identity:|
      assert_equal ['AC-test-account', 'SK-test-key', 'test-api-secret'], [account_sid, api_key, api_secret]
      @issued_identity = identity
      @issued_service = grants.fetch(0).service_sid
      OpenStruct.new(to_jwt: 'test-chat-access-token')
    end

    with_test_environment(
      'TWILIO_ACCOUNT_SID' => 'AC-test-account', 'TWILIO_AUTH_TOKEN' => 'test-auth-token',
      'TWILIO_API_KEY' => 'SK-test-key', 'TWILIO_API_SECRET' => 'test-api-secret',
      'TWILIO_SERVICE_SID' => 'IS-test-service'
    ) do
      Twilio::REST::Client.stub(:new, client) do
        Twilio::JWT::AccessToken.stub(:new, issuer) { yield }
      end
    end
  end
end
