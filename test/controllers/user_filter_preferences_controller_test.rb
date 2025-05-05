require 'test_helper'

class UserFilterPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_filter_preference = user_filter_preferences(:one)
  end

  test "should get index" do
    get user_filter_preferences_url
    assert_response :success
  end

  test "should get new" do
    get new_user_filter_preference_url
    assert_response :success
  end

  test "should create user_filter_preference" do
    assert_difference('UserFilterPreference.count') do
      post user_filter_preferences_url, params: { user_filter_preference: { age_from: @user_filter_preference.age_from, age_till: @user_filter_preference.age_till, distance_range: @user_filter_preference.distance_range, gender: @user_filter_preference.gender, user_id: @user_filter_preference.user_id } }
    end

    assert_redirected_to user_filter_preference_url(UserFilterPreference.last)
  end

  test "should show user_filter_preference" do
    get user_filter_preference_url(@user_filter_preference)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_filter_preference_url(@user_filter_preference)
    assert_response :success
  end

  test "should update user_filter_preference" do
    patch user_filter_preference_url(@user_filter_preference), params: { user_filter_preference: { age_from: @user_filter_preference.age_from, age_till: @user_filter_preference.age_till, distance_range: @user_filter_preference.distance_range, gender: @user_filter_preference.gender, user_id: @user_filter_preference.user_id } }
    assert_redirected_to user_filter_preference_url(@user_filter_preference)
  end

  test "should destroy user_filter_preference" do
    assert_difference('UserFilterPreference.count', -1) do
      delete user_filter_preference_url(@user_filter_preference)
    end

    assert_redirected_to user_filter_preferences_url
  end
end
