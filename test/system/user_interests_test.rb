require "application_system_test_case"

class UserInterestsTest < ApplicationSystemTestCase
  setup do
    @user_interest = user_interests(:one)
  end

  test "visiting the index" do
    visit user_interests_url
    assert_selector "h1", text: "User Interests"
  end

  test "creating a User interest" do
    visit user_interests_url
    click_on "New User Interest"

    fill_in "Interest", with: @user_interest.interest_id
    fill_in "User", with: @user_interest.user_id
    click_on "Create User interest"

    assert_text "User interest was successfully created"
    click_on "Back"
  end

  test "updating a User interest" do
    visit user_interests_url
    click_on "Edit", match: :first

    fill_in "Interest", with: @user_interest.interest_id
    fill_in "User", with: @user_interest.user_id
    click_on "Update User interest"

    assert_text "User interest was successfully updated"
    click_on "Back"
  end

  test "destroying a User interest" do
    visit user_interests_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User interest was successfully destroyed"
  end
end
