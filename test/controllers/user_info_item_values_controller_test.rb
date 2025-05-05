require 'test_helper'

class UserInfoItemValuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_info_item_value = user_info_item_values(:one)
  end

  test "should get index" do
    get user_info_item_values_url
    assert_response :success
  end

  test "should get new" do
    get new_user_info_item_value_url
    assert_response :success
  end

  test "should create user_info_item_value" do
    assert_difference('UserInfoItemValue.count') do
      post user_info_item_values_url, params: { user_info_item_value: { info_item_value_id: @user_info_item_value.info_item_value_id, user_id: @user_info_item_value.user_id } }
    end

    assert_redirected_to user_info_item_value_url(UserInfoItemValue.last)
  end

  test "should show user_info_item_value" do
    get user_info_item_value_url(@user_info_item_value)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_info_item_value_url(@user_info_item_value)
    assert_response :success
  end

  test "should update user_info_item_value" do
    patch user_info_item_value_url(@user_info_item_value), params: { user_info_item_value: { info_item_value_id: @user_info_item_value.info_item_value_id, user_id: @user_info_item_value.user_id } }
    assert_redirected_to user_info_item_value_url(@user_info_item_value)
  end

  test "should destroy user_info_item_value" do
    assert_difference('UserInfoItemValue.count', -1) do
      delete user_info_item_value_url(@user_info_item_value)
    end

    assert_redirected_to user_info_item_values_url
  end
end
