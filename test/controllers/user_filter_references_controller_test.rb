require 'test_helper'

class UserFilterReferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_filter_reference = user_filter_references(:one)
  end

  test "should get index" do
    get user_filter_references_url
    assert_response :success
  end

  test "should get new" do
    get new_user_filter_reference_url
    assert_response :success
  end

  test "should create user_filter_reference" do
    assert_difference('UserFilterReference.count') do
      post user_filter_references_url, params: { user_filter_reference: { age_from: @user_filter_reference.age_from, age_till: @user_filter_reference.age_till, distance_range: @user_filter_reference.distance_range, gender: @user_filter_reference.gender, user_id: @user_filter_reference.user_id } }
    end

    assert_redirected_to user_filter_reference_url(UserFilterReference.last)
  end

  test "should show user_filter_reference" do
    get user_filter_reference_url(@user_filter_reference)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_filter_reference_url(@user_filter_reference)
    assert_response :success
  end

  test "should update user_filter_reference" do
    patch user_filter_reference_url(@user_filter_reference), params: { user_filter_reference: { age_from: @user_filter_reference.age_from, age_till: @user_filter_reference.age_till, distance_range: @user_filter_reference.distance_range, gender: @user_filter_reference.gender, user_id: @user_filter_reference.user_id } }
    assert_redirected_to user_filter_reference_url(@user_filter_reference)
  end

  test "should destroy user_filter_reference" do
    assert_difference('UserFilterReference.count', -1) do
      delete user_filter_reference_url(@user_filter_reference)
    end

    assert_redirected_to user_filter_references_url
  end
end
