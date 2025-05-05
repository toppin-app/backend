require "application_system_test_case"

class UserInfoItemValuesTest < ApplicationSystemTestCase
  setup do
    @user_info_item_value = user_info_item_values(:one)
  end

  test "visiting the index" do
    visit user_info_item_values_url
    assert_selector "h1", text: "User Info Item Values"
  end

  test "creating a User info item value" do
    visit user_info_item_values_url
    click_on "New User Info Item Value"

    fill_in "Info item value", with: @user_info_item_value.info_item_value_id
    fill_in "User", with: @user_info_item_value.user_id
    click_on "Create User info item value"

    assert_text "User info item value was successfully created"
    click_on "Back"
  end

  test "updating a User info item value" do
    visit user_info_item_values_url
    click_on "Edit", match: :first

    fill_in "Info item value", with: @user_info_item_value.info_item_value_id
    fill_in "User", with: @user_info_item_value.user_id
    click_on "Update User info item value"

    assert_text "User info item value was successfully updated"
    click_on "Back"
  end

  test "destroying a User info item value" do
    visit user_info_item_values_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User info item value was successfully destroyed"
  end
end
