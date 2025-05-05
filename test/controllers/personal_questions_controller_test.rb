require 'test_helper'

class PersonalQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @personal_question = personal_questions(:one)
  end

  test "should get index" do
    get personal_questions_url
    assert_response :success
  end

  test "should get new" do
    get new_personal_question_url
    assert_response :success
  end

  test "should create personal_question" do
    assert_difference('PersonalQuestion.count') do
      post personal_questions_url, params: { personal_question: { name: @personal_question.name } }
    end

    assert_redirected_to personal_question_url(PersonalQuestion.last)
  end

  test "should show personal_question" do
    get personal_question_url(@personal_question)
    assert_response :success
  end

  test "should get edit" do
    get edit_personal_question_url(@personal_question)
    assert_response :success
  end

  test "should update personal_question" do
    patch personal_question_url(@personal_question), params: { personal_question: { name: @personal_question.name } }
    assert_redirected_to personal_question_url(@personal_question)
  end

  test "should destroy personal_question" do
    assert_difference('PersonalQuestion.count', -1) do
      delete personal_question_url(@personal_question)
    end

    assert_redirected_to personal_questions_url
  end
end
