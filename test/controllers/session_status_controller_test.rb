require 'test_helper'
require 'minitest/mock'

class SessionStatusControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @user = User.create!(email: 'session-status@example.com', password: 'Secure123!', name: 'Session User')
    @token, @payload = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil)
  end

  test 'valid token returns only identity without rotating token or updating user' do
    before = @user.reload.attributes
    get_status(@token)
    assert_response :ok
    assert_equal({ 'id' => @user.id }, response.parsed_body)
    assert_includes response.headers['Cache-Control'].split(',').map(&:strip), 'no-store'
    assert_nil response.headers['Authorization']
    assert_equal before, @user.reload.attributes
  end

  test 'missing token is refused even with a valid session cookie' do
    sign_in @user
    get '/session.json'
    assert_response :unauthorized
  end

  test 'invalid signature is refused even with a valid session cookie' do
    sign_in @user
    get_status(JWT.encode(@payload, 'incorrect-test-secret', 'HS256'))
    assert_response :unauthorized
  end

  test 'expired signed token is refused' do
    get_status(Warden::JWTAuth::TokenEncoder.new.call(@payload.merge('exp' => 1)))
    assert_response :unauthorized
  end

  test 'revoked token is refused' do
    @user.update!(jti: SecureRandom.uuid)
    get_status(@token)
    assert_response :unauthorized
  end

  test 'blocked user is refused' do
    @user.update!(blocked: true)
    get_status(@token)
    assert_response :forbidden
  end

  test 'soft deleted user is refused' do
    @user.update!(deleted_account: true)
    get_status(@token)
    assert_response :unauthorized
  end

  test 'wrong scope or audience is refused' do
    [{ 'scp' => 'admin' }, { 'aud' => 'other-app' }].each do |claims|
      get_status(Warden::JWTAuth::TokenEncoder.new.call(@payload.merge(claims)))
      assert_response :unauthorized
    end
  end

  test 'malformed bearer values are refused without exposing details' do
    ['', 'invalid', 'Bearer invalid', "Bearer #{@token} extra"].each do |value|
      get '/session.json', headers: { 'Authorization' => value }
      assert_response :unauthorized
      assert_empty response.body
    end
  end

  private

  def get_status(token)
    get '/session.json', headers: { 'Authorization' => "Bearer #{token}" }
  end
end
