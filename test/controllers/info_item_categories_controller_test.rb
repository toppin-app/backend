require 'test_helper'

class InfoItemCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @info_item_category = info_item_categories(:one)
  end

  test "should get index" do
    get info_item_categories_url
    assert_response :success
  end

  test "should get new" do
    get new_info_item_category_url
    assert_response :success
  end

  test "should create info_item_category" do
    assert_difference('InfoItemCategory.count') do
      post info_item_categories_url, params: { info_item_category: { name: @info_item_category.name } }
    end

    assert_redirected_to info_item_category_url(InfoItemCategory.last)
  end

  test "should show info_item_category" do
    get info_item_category_url(@info_item_category)
    assert_response :success
  end

  test "should get edit" do
    get edit_info_item_category_url(@info_item_category)
    assert_response :success
  end

  test "should update info_item_category" do
    patch info_item_category_url(@info_item_category), params: { info_item_category: { name: @info_item_category.name } }
    assert_redirected_to info_item_category_url(@info_item_category)
  end

  test "should destroy info_item_category" do
    assert_difference('InfoItemCategory.count', -1) do
      delete info_item_category_url(@info_item_category)
    end

    assert_redirected_to info_item_categories_url
  end
end
