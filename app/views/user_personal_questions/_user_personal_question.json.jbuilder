json.extract! user_personal_question, :id, :user_id, :personal_question_id, :answer, :created_at, :updated_at
json.url user_personal_question_url(user_personal_question, format: :json)
