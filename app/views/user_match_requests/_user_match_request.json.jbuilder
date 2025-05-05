json.extract! user_match_request, :id, :is_match, :is_paid, :is_sugar_sweet, :is_rejected, :match_date, :twilio_conversation_sid, :is_superlike, :created_at
json.target user_match_request.target, :id, :name, :user_media,:user_media_url, :verified, :instagram, :gender, :current_subscription_id, :current_subscription_name, :is_connected, :verified
json.user user_match_request.user, :id, :name, :user_media,:user_media_url, :current_subscription_id, :instagram, :gender, :current_subscription_name, :is_connected, :verified
#json.target @target_users.select { |user| user.id == user_match_request.target_user }.first
