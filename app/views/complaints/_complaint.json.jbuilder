json.extract! complaint, :id, :user_id, :to_user_id, :reason, :text, :created_at, :updated_at
json.url complaint_url(complaint, format: :json)
