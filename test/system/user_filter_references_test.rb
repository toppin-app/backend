require "application_system_test_case"

class UserFilterReferencesTest < ApplicationSystemTestCase
  setup do
    @user_filter_reference = user_filter_references(:one)
  end

  test "visiting the index" do
    visit user_filter_references_url
    assert_selector "h1", text: "User Filter References"
  end

  test "creating a User filter reference" do
    visit user_filter_references_url
    click_on "New User Filter Reference"

    fill_in "Age from", with: @user_filter_reference.age_from
    fill_in "Age till", with: @user_filter_reference.age_till
    fill_in "Distance range", with: @user_filter_reference.distance_range
    fill_in "Gender", with: @user_filter_reference.gender
    fill_in "User", with: @user_filter_reference.user_id
    click_on "Create User filter reference"

    assert_text "User filter reference was successfully created"
    click_on "Back"
  end

  test "updating a User filter reference" do
    visit user_filter_references_url
    click_on "Edit", match: :first

    fill_in "Age from", with: @user_filter_reference.age_from
    fill_in "Age till", with: @user_filter_reference.age_till
    fill_in "Distance range", with: @user_filter_reference.distance_range
    fill_in "Gender", with: @user_filter_reference.gender
    fill_in "User", with: @user_filter_reference.user_id
    click_on "Update User filter reference"

    assert_text "User filter reference was successfully updated"
    click_on "Back"
  end

  test "destroying a User filter reference" do
    visit user_filter_references_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User filter reference was successfully destroyed"
  end
end
