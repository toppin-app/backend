require 'test_helper'

class SubscriptionAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []
  setup do
    @user = User.create!(email: 'access@example.com', password: 'Secure123!')
    sign_in @user
  end

  test 'KNOWN BUG unverified legacy purchase grants the caller supreme' do
    post '/purchases.json', params: { purchase: { product_id: 'toppin_supreme_mensual', validated: false } }, as: :json
    assert_response :created
    assert_equal 'supreme', @user.reload.current_subscription_name
  end

  test 'KNOWN BUG caller can assign an unverified purchase to another user' do
    other = User.create!(email: 'other-access@example.com', password: 'Secure123!')
    post '/purchases.json', params: { purchase: { user_id: other.id, product_id: 'toppin_premium_mensual' } }, as: :json
    assert_response :created
    assert_equal 'premium', other.reload.current_subscription_name
  end

  test 'unauthenticated purchase is rejected' do
    sign_out @user
    assert_no_difference('Purchase.count') do
      post '/purchases.json', params: { purchase: { product_id: 'toppin_supreme_mensual' } }, as: :json
    end
    assert_response :unauthorized
  end

  test 'ordinary profile edit cannot escalate subscription' do
    put "/users/#{@user.id}.json", params: { user: { current_subscription_name: 'supreme' } }, as: :json
    assert_nil @user.reload.current_subscription_name
  end

  test 'KNOWN BUG free account can roll back through the API' do
    other = User.create!(email: 'rollback@example.com', password: 'Secure123!')
    row = UserMatchRequest.create!(user: @user, target_user: other.id, is_like: true)
    put '/users/rollback.json', params: { target_user_id: other.id }, as: :json
    assert_response :success
    assert_not UserMatchRequest.exists?(row.id)
  end

  [nil, '', 'premium', 'supreme', 'free', 'null', 'unknown'].each do |level|
    test "advertising toggle access for #{level.inspect}" do
      @user.update!(current_subscription_name: level, show_publi: true)
      post '/toggle_publi.json', as: :json
      allowed = %w[premium supreme].include?(level)
      assert_response(allowed ? :success : :bad_request)
      assert_equal !allowed, @user.reload.show_publi
    end
  end

  test 'KNOWN BUG expired premium still disables advertising' do
    @user.update!(current_subscription_name: 'premium', current_subscription_expires: 1.day.ago)
    post '/toggle_publi.json', as: :json
    assert_response :success
  end
end
