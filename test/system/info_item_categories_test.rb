require "application_system_test_case"

class InfoItemCategoriesTest < ApplicationSystemTestCase
  setup do
    @info_item_category = info_item_categories(:one)
  end

  test "visiting the index" do
    visit info_item_categories_url
    assert_selector "h1", text: "Info Item Categories"
  end

  test "creating a Info item category" do
    visit info_item_categories_url
    click_on "New Info Item Category"

    fill_in "Name", with: @info_item_category.name
    click_on "Create Info item category"

    assert_text "Info item category was successfully created"
    click_on "Back"
  end

  test "updating a Info item category" do
    visit info_item_categories_url
    click_on "Edit", match: :first

    fill_in "Name", with: @info_item_category.name
    click_on "Update Info item category"

    assert_text "Info item category was successfully updated"
    click_on "Back"
  end

  test "destroying a Info item category" do
    visit info_item_categories_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Info item category was successfully destroyed"
  end
end
