require 'test_helper'

class UserInterestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_interest = user_interests(:one)
  end

  test "should get index" do
    get user_interests_url
    assert_response :success
  end

  test "should get new" do
    get new_user_interest_url
    assert_response :success
  end

  test "should create user_interest" do
    assert_difference('UserInterest.count') do
      post user_interests_url, params: { user_interest: { interest_id: @user_interest.interest_id, user_id: @user_interest.user_id } }
    end

    assert_redirected_to user_interest_url(UserInterest.last)
  end

  test "should show user_interest" do
    get user_interest_url(@user_interest)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_interest_url(@user_interest)
    assert_response :success
  end

  test "should update user_interest" do
    patch user_interest_url(@user_interest), params: { user_interest: { interest_id: @user_interest.interest_id, user_id: @user_interest.user_id } }
    assert_redirected_to user_interest_url(@user_interest)
  end

  test "should destroy user_interest" do
    assert_difference('UserInterest.count', -1) do
      delete user_interest_url(@user_interest)
    end

    assert_redirected_to user_interests_url
  end
end
