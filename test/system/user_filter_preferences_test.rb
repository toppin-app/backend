require "application_system_test_case"

class UserFilterPreferencesTest < ApplicationSystemTestCase
  setup do
    @user_filter_preference = user_filter_preferences(:one)
  end

  test "visiting the index" do
    visit user_filter_preferences_url
    assert_selector "h1", text: "User Filter Preferences"
  end

  test "creating a User filter preference" do
    visit user_filter_preferences_url
    click_on "New User Filter Preference"

    fill_in "Age from", with: @user_filter_preference.age_from
    fill_in "Age till", with: @user_filter_preference.age_till
    fill_in "Distance range", with: @user_filter_preference.distance_range
    fill_in "Gender", with: @user_filter_preference.gender
    fill_in "User", with: @user_filter_preference.user_id
    click_on "Create User filter preference"

    assert_text "User filter preference was successfully created"
    click_on "Back"
  end

  test "updating a User filter preference" do
    visit user_filter_preferences_url
    click_on "Edit", match: :first

    fill_in "Age from", with: @user_filter_preference.age_from
    fill_in "Age till", with: @user_filter_preference.age_till
    fill_in "Distance range", with: @user_filter_preference.distance_range
    fill_in "Gender", with: @user_filter_preference.gender
    fill_in "User", with: @user_filter_preference.user_id
    click_on "Update User filter preference"

    assert_text "User filter preference was successfully updated"
    click_on "Back"
  end

  test "destroying a User filter preference" do
    visit user_filter_preferences_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User filter preference was successfully destroyed"
  end
end
