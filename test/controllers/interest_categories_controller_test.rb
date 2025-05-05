require 'test_helper'

class InterestCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @interest_category = interest_categories(:one)
  end

  test "should get index" do
    get interest_categories_url
    assert_response :success
  end

  test "should get new" do
    get new_interest_category_url
    assert_response :success
  end

  test "should create interest_category" do
    assert_difference('InterestCategory.count') do
      post interest_categories_url, params: { interest_category: { name: @interest_category.name } }
    end

    assert_redirected_to interest_category_url(InterestCategory.last)
  end

  test "should show interest_category" do
    get interest_category_url(@interest_category)
    assert_response :success
  end

  test "should get edit" do
    get edit_interest_category_url(@interest_category)
    assert_response :success
  end

  test "should update interest_category" do
    patch interest_category_url(@interest_category), params: { interest_category: { name: @interest_category.name } }
    assert_redirected_to interest_category_url(@interest_category)
  end

  test "should destroy interest_category" do
    assert_difference('InterestCategory.count', -1) do
      delete interest_category_url(@interest_category)
    end

    assert_redirected_to interest_categories_url
  end
end
