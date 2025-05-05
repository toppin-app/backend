require 'test_helper'

class UserMediaControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_medium = user_media(:one)
  end

  test "should get index" do
    get user_media_url
    assert_response :success
  end

  test "should get new" do
    get new_user_medium_url
    assert_response :success
  end

  test "should create user_medium" do
    assert_difference('UserMedium.count') do
      post user_media_url, params: { user_medium: { file: @user_medium.file, position: @user_medium.position, user_id: @user_medium.user_id } }
    end

    assert_redirected_to user_medium_url(UserMedium.last)
  end

  test "should show user_medium" do
    get user_medium_url(@user_medium)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_medium_url(@user_medium)
    assert_response :success
  end

  test "should update user_medium" do
    patch user_medium_url(@user_medium), params: { user_medium: { file: @user_medium.file, position: @user_medium.position, user_id: @user_medium.user_id } }
    assert_redirected_to user_medium_url(@user_medium)
  end

  test "should destroy user_medium" do
    assert_difference('UserMedium.count', -1) do
      delete user_medium_url(@user_medium)
    end

    assert_redirected_to user_media_url
  end
end
