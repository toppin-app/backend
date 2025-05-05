require 'test_helper'

class UserPersonalQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_personal_question = user_personal_questions(:one)
  end

  test "should get index" do
    get user_personal_questions_url
    assert_response :success
  end

  test "should get new" do
    get new_user_personal_question_url
    assert_response :success
  end

  test "should create user_personal_question" do
    assert_difference('UserPersonalQuestion.count') do
      post user_personal_questions_url, params: { user_personal_question: { answer: @user_personal_question.answer, personal_question_id: @user_personal_question.personal_question_id, user_id: @user_personal_question.user_id } }
    end

    assert_redirected_to user_personal_question_url(UserPersonalQuestion.last)
  end

  test "should show user_personal_question" do
    get user_personal_question_url(@user_personal_question)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_personal_question_url(@user_personal_question)
    assert_response :success
  end

  test "should update user_personal_question" do
    patch user_personal_question_url(@user_personal_question), params: { user_personal_question: { answer: @user_personal_question.answer, personal_question_id: @user_personal_question.personal_question_id, user_id: @user_personal_question.user_id } }
    assert_redirected_to user_personal_question_url(@user_personal_question)
  end

  test "should destroy user_personal_question" do
    assert_difference('UserPersonalQuestion.count', -1) do
      delete user_personal_question_url(@user_personal_question)
    end

    assert_redirected_to user_personal_questions_url
  end
end
