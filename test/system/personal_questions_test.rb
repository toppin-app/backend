require "application_system_test_case"

class PersonalQuestionsTest < ApplicationSystemTestCase
  setup do
    @personal_question = personal_questions(:one)
  end

  test "visiting the index" do
    visit personal_questions_url
    assert_selector "h1", text: "Personal Questions"
  end

  test "creating a Personal question" do
    visit personal_questions_url
    click_on "New Personal Question"

    fill_in "Name", with: @personal_question.name
    click_on "Create Personal question"

    assert_text "Personal question was successfully created"
    click_on "Back"
  end

  test "updating a Personal question" do
    visit personal_questions_url
    click_on "Edit", match: :first

    fill_in "Name", with: @personal_question.name
    click_on "Update Personal question"

    assert_text "Personal question was successfully updated"
    click_on "Back"
  end

  test "destroying a Personal question" do
    visit personal_questions_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Personal question was successfully destroyed"
  end
end
