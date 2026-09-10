require 'test_helper'
require 'minitest/mock'

class Users::LoginThrottlingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test 'rejects before user lookup with retry metadata and no token' do
    User.stub(:find_by, ->(*) { flunk 'Password lookup must not run' }) do
      LoginAttemptLimiter.stub(:check, 42) do
        post '/login.json', params: { user: { email: 'unknown@example.com', password: 'secret' } }, as: :json
      end
    end
    assert_response :too_many_requests
    assert_equal '42', response.headers['Retry-After']
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'login_rate_limited', response.parsed_body['code']
    assert_equal 42, response.parsed_body['retry_after']
    assert_nil response.headers['Authorization']
    assert_not_includes response.body, 'unknown@example.com'
    assert_not_includes response.body, 'secret'
  end

  test 'HTML login is protected too' do
    LoginAttemptLimiter.stub(:check, 20) do
      post '/login', params: { user: { email: 'unknown@example.com', password: 'secret' } }
    end
    assert_response :too_many_requests
    assert_equal '20', response.headers['Retry-After']
  end

  test 'ordinary invalid credentials retain their contract below the limit' do
    LoginAttemptLimiter.stub(:check, 0) do
      post '/login.json', params: { user: { email: 'unknown@example.com', password: 'secret' } }, as: :json
    end
    assert_response :bad_request
    assert_nil response.headers['Retry-After']
  end

  test 'missing user envelope can still be throttled' do
    LoginAttemptLimiter.stub(:check, 30) { post '/login.json', params: {}, as: :json }
    assert_response :too_many_requests
  end
end
