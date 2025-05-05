class AddTwilioConversationSidToUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_match_requests, :twilio_conversation_sid, :string
  end
end
