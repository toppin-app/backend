require "application_system_test_case"

class InterestCategoriesTest < ApplicationSystemTestCase
  setup do
    @interest_category = interest_categories(:one)
  end

  test "visiting the index" do
    visit interest_categories_url
    assert_selector "h1", text: "Interest Categories"
  end

  test "creating a Interest category" do
    visit interest_categories_url
    click_on "New Interest Category"

    fill_in "Name", with: @interest_category.name
    click_on "Create Interest category"

    assert_text "Interest category was successfully created"
    click_on "Back"
  end

  test "updating a Interest category" do
    visit interest_categories_url
    click_on "Edit", match: :first

    fill_in "Name", with: @interest_category.name
    click_on "Update Interest category"

    assert_text "Interest category was successfully updated"
    click_on "Back"
  end

  test "destroying a Interest category" do
    visit interest_categories_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Interest category was successfully destroyed"
  end
end
