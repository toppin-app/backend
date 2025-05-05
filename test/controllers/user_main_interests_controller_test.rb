require 'test_helper'

class UserMainInterestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_main_interest = user_main_interests(:one)
  end

  test "should get index" do
    get user_main_interests_url
    assert_response :success
  end

  test "should get new" do
    get new_user_main_interest_url
    assert_response :success
  end

  test "should create user_main_interest" do
    assert_difference('UserMainInterest.count') do
      post user_main_interests_url, params: { user_main_interest: { interest_id: @user_main_interest.interest_id, name: @user_main_interest.name, percentage: @user_main_interest.percentage, user_id: @user_main_interest.user_id } }
    end

    assert_redirected_to user_main_interest_url(UserMainInterest.last)
  end

  test "should show user_main_interest" do
    get user_main_interest_url(@user_main_interest)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_main_interest_url(@user_main_interest)
    assert_response :success
  end

  test "should update user_main_interest" do
    patch user_main_interest_url(@user_main_interest), params: { user_main_interest: { interest_id: @user_main_interest.interest_id, name: @user_main_interest.name, percentage: @user_main_interest.percentage, user_id: @user_main_interest.user_id } }
    assert_redirected_to user_main_interest_url(@user_main_interest)
  end

  test "should destroy user_main_interest" do
    assert_difference('UserMainInterest.count', -1) do
      delete user_main_interest_url(@user_main_interest)
    end

    assert_redirected_to user_main_interests_url
  end
end
