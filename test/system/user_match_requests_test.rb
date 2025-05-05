require "application_system_test_case"

class UserMatchRequestsTest < ApplicationSystemTestCase
  setup do
    @user_match_request = user_match_requests(:one)
  end

  test "visiting the index" do
    visit user_match_requests_url
    assert_selector "h1", text: "User Match Requests"
  end

  test "creating a User match request" do
    visit user_match_requests_url
    click_on "New User Match Request"

    fill_in "Affinity index", with: @user_match_request.affinity_index
    check "Is match" if @user_match_request.is_match
    fill_in "Is paid", with: @user_match_request.is_paid
    check "Is rejected" if @user_match_request.is_rejected
    fill_in "Target user", with: @user_match_request.target_user
    fill_in "User", with: @user_match_request.user_id
    click_on "Create User match request"

    assert_text "User match request was successfully created"
    click_on "Back"
  end

  test "updating a User match request" do
    visit user_match_requests_url
    click_on "Edit", match: :first

    fill_in "Affinity index", with: @user_match_request.affinity_index
    check "Is match" if @user_match_request.is_match
    fill_in "Is paid", with: @user_match_request.is_paid
    check "Is rejected" if @user_match_request.is_rejected
    fill_in "Target user", with: @user_match_request.target_user
    fill_in "User", with: @user_match_request.user_id
    click_on "Update User match request"

    assert_text "User match request was successfully updated"
    click_on "Back"
  end

  test "destroying a User match request" do
    visit user_match_requests_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User match request was successfully destroyed"
  end
end
