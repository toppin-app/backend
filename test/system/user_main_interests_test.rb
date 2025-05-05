require "application_system_test_case"

class UserMainInterestsTest < ApplicationSystemTestCase
  setup do
    @user_main_interest = user_main_interests(:one)
  end

  test "visiting the index" do
    visit user_main_interests_url
    assert_selector "h1", text: "User Main Interests"
  end

  test "creating a User main interest" do
    visit user_main_interests_url
    click_on "New User Main Interest"

    fill_in "Interest", with: @user_main_interest.interest_id
    fill_in "Name", with: @user_main_interest.name
    fill_in "Percentage", with: @user_main_interest.percentage
    fill_in "User", with: @user_main_interest.user_id
    click_on "Create User main interest"

    assert_text "User main interest was successfully created"
    click_on "Back"
  end

  test "updating a User main interest" do
    visit user_main_interests_url
    click_on "Edit", match: :first

    fill_in "Interest", with: @user_main_interest.interest_id
    fill_in "Name", with: @user_main_interest.name
    fill_in "Percentage", with: @user_main_interest.percentage
    fill_in "User", with: @user_main_interest.user_id
    click_on "Update User main interest"

    assert_text "User main interest was successfully updated"
    click_on "Back"
  end

  test "destroying a User main interest" do
    visit user_main_interests_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User main interest was successfully destroyed"
  end
end
