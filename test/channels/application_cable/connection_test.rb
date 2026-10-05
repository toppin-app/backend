require 'test_helper'
require_relative '../../support/t03_boundary_helpers'

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  include T03BoundaryHelpers
  self.fixture_table_names = []

  setup do
    @user = create_boundary_user
    @previous_secret = ENV['DEVISE_JWT_SECRET_KEY']
    ENV['DEVISE_JWT_SECRET_KEY'] = Warden::JWTAuth.config.secret
  end

  teardown do
    ENV['DEVISE_JWT_SECRET_KEY'] = @previous_secret
  end

  test 'a signed JWT identifies the persisted user with and without Bearer prefix' do
    token = authorization_for(@user)['Authorization']
    connect params: { token: token }
    assert_equal @user.id, connection.current_user.id

    disconnect
    connect params: { token: token.delete_prefix('Bearer ') }
    assert_equal @user.id, connection.current_user.id
  end

  test 'an admin connects as its own identity' do
    admin = create_boundary_user(admin: true)
    connect params: { token: authorization_for(admin)['Authorization'] }
    assert_equal admin.id, connection.current_user.id
  end

  test 'a third party token cannot select another connection identity through params' do
    other = create_boundary_user
    connect params: { token: authorization_for(other)['Authorization'], user_id: @user.id }
    assert_equal other.id, connection.current_user.id
  end

  test 'an anonymous connection is rejected' do
    assert_reject_connection { connect }
  end

  test 'malformed and incorrectly signed JWTs are rejected' do
    invalid_signature = JWT.encode({ sub: @user.id.to_s, exp: 1.hour.from_now.to_i }, 'wrong-test-secret', 'HS256')
    ['not-a-jwt', invalid_signature].each do |token|
      assert_reject_connection { connect params: { token: token } }
    end
  end

  test 'an expired JWT is rejected' do
    assert_reject_connection do
      connect params: { token: authorization_for(@user, exp: 1.second.ago.to_i)['Authorization'] }
    end
  end

  test 'a signed JWT naming a missing user is rejected' do
    token = authorization_for(@user, sub: '0')['Authorization']
    assert_reject_connection { connect params: { token: token } }
  end

  # T33: known vulnerability. Passing these characterization tests does NOT
  # approve access; replace their expectations when revocation/status is fixed.
  test 'T33 characterization accepts a JWT whose jti has been revoked' do
    token = authorization_for(@user)['Authorization']
    @user.update!(jti: SecureRandom.uuid)
    connect params: { token: token }
    assert_equal @user.id, connection.current_user.id
  end

  test 'T33 characterization accepts a blocked account over websocket' do
    @user.update!(blocked: true)
    connect params: { token: authorization_for(@user)['Authorization'] }
    assert_equal @user.id, connection.current_user.id
  end

  test 'T33 characterization accepts a soft deleted account over websocket' do
    @user.update!(deleted_account: true)
    connect params: { token: authorization_for(@user)['Authorization'] }
    assert_equal @user.id, connection.current_user.id
  end
end
