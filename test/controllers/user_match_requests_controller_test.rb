require 'test_helper'

class UserMatchRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_match_request = user_match_requests(:one)
  end

  test "should get index" do
    get user_match_requests_url
    assert_response :success
  end

  test "should get new" do
    get new_user_match_request_url
    assert_response :success
  end

  test "should create user_match_request" do
    assert_difference('UserMatchRequest.count') do
      post user_match_requests_url, params: { user_match_request: { affinity_index: @user_match_request.affinity_index, is_match: @user_match_request.is_match, is_paid: @user_match_request.is_paid, is_rejected: @user_match_request.is_rejected, target_user: @user_match_request.target_user, user_id: @user_match_request.user_id } }
    end

    assert_redirected_to user_match_request_url(UserMatchRequest.last)
  end

  test "should show user_match_request" do
    get user_match_request_url(@user_match_request)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_match_request_url(@user_match_request)
    assert_response :success
  end

  test "should update user_match_request" do
    patch user_match_request_url(@user_match_request), params: { user_match_request: { affinity_index: @user_match_request.affinity_index, is_match: @user_match_request.is_match, is_paid: @user_match_request.is_paid, is_rejected: @user_match_request.is_rejected, target_user: @user_match_request.target_user, user_id: @user_match_request.user_id } }
    assert_redirected_to user_match_request_url(@user_match_request)
  end

  test "should destroy user_match_request" do
    assert_difference('UserMatchRequest.count', -1) do
      delete user_match_request_url(@user_match_request)
    end

    assert_redirected_to user_match_requests_url
  end
end
