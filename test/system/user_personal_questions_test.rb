require "application_system_test_case"

class UserPersonalQuestionsTest < ApplicationSystemTestCase
  setup do
    @user_personal_question = user_personal_questions(:one)
  end

  test "visiting the index" do
    visit user_personal_questions_url
    assert_selector "h1", text: "User Personal Questions"
  end

  test "creating a User personal question" do
    visit user_personal_questions_url
    click_on "New User Personal Question"

    fill_in "Answer", with: @user_personal_question.answer
    fill_in "Personal question", with: @user_personal_question.personal_question_id
    fill_in "User", with: @user_personal_question.user_id
    click_on "Create User personal question"

    assert_text "User personal question was successfully created"
    click_on "Back"
  end

  test "updating a User personal question" do
    visit user_personal_questions_url
    click_on "Edit", match: :first

    fill_in "Answer", with: @user_personal_question.answer
    fill_in "Personal question", with: @user_personal_question.personal_question_id
    fill_in "User", with: @user_personal_question.user_id
    click_on "Update User personal question"

    assert_text "User personal question was successfully updated"
    click_on "Back"
  end

  test "destroying a User personal question" do
    visit user_personal_questions_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "User personal question was successfully destroyed"
  end
end
