require 'test_helper'

class InfoItemValuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @info_item_value = info_item_values(:one)
  end

  test "should get index" do
    get info_item_values_url
    assert_response :success
  end

  test "should get new" do
    get new_info_item_value_url
    assert_response :success
  end

  test "should create info_item_value" do
    assert_difference('InfoItemValue.count') do
      post info_item_values_url, params: { info_item_value: { info_item_category_id: @info_item_value.info_item_category_id, name: @info_item_value.name } }
    end

    assert_redirected_to info_item_value_url(InfoItemValue.last)
  end

  test "should show info_item_value" do
    get info_item_value_url(@info_item_value)
    assert_response :success
  end

  test "should get edit" do
    get edit_info_item_value_url(@info_item_value)
    assert_response :success
  end

  test "should update info_item_value" do
    patch info_item_value_url(@info_item_value), params: { info_item_value: { info_item_category_id: @info_item_value.info_item_category_id, name: @info_item_value.name } }
    assert_redirected_to info_item_value_url(@info_item_value)
  end

  test "should destroy info_item_value" do
    assert_difference('InfoItemValue.count', -1) do
      delete info_item_value_url(@info_item_value)
    end

    assert_redirected_to info_item_values_url
  end
end
