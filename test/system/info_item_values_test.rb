require "application_system_test_case"

class InfoItemValuesTest < ApplicationSystemTestCase
  setup do
    @info_item_value = info_item_values(:one)
  end

  test "visiting the index" do
    visit info_item_values_url
    assert_selector "h1", text: "Info Item Values"
  end

  test "creating a Info item value" do
    visit info_item_values_url
    click_on "New Info Item Value"

    fill_in "Info item category", with: @info_item_value.info_item_category_id
    fill_in "Value", with: @info_item_value.name
    click_on "Create Info item value"

    assert_text "Info item value was successfully created"
    click_on "Back"
  end

  test "updating a Info item value" do
    visit info_item_values_url
    click_on "Edit", match: :first

    fill_in "Info item category", with: @info_item_value.info_item_category_id
    fill_in "Value", with: @info_item_value.name
    click_on "Update Info item value"

    assert_text "Info item value was successfully updated"
    click_on "Back"
  end

  test "destroying a Info item value" do
    visit info_item_values_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Info item value was successfully destroyed"
  end
end
