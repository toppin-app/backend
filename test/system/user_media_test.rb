require "application_system_test_case"

class UserMediaTest < ApplicationSystemTestCase
  setup do
    @user_medium = user_media(:one)
  end

  test "visiting the index" do
    visit user_media_url
    assert_selector "h1", text: "User Media"
  end

  test "creating a User medium" do
    visit user_media_url
    click_on "New User Medium"

    fill_in "File", with: @user_medium.file
    fill_in "Position", with: @user_medium.position
    fill_in "User", with: @user_medium.user_id
    click_on "Create User medium"

    assert_text "User medium was successfully created"
    click_on "Back"
  end

  test "updating a User medium" do
    visit user_media_url
    click_on "Edit", match: :first

    fill_in "File", with: @user_medium.file
    fill_in "Position", with: @user_medium.position
    fill_in "User", with: @user_medium.user_id
    click_on "Update User medium"

    assert_text "User medium was successfully updated"
    click_on "Back"
  end

  test "destroying a User medium" do
    visit user_media_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User medium was successfully destroyed"
  end
end
