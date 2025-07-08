class AdminController < ApplicationController
  before_action :authenticate_user!
  
  def index
    check_admin
    @title = "Panel de control administración"
  end


  def test_conversation
    twilio = TwilioController.new
    UserMatchRequest.create(user_id: params[:user_1], target_user: params[:user_2])
    conv = twilio.create_conversation(params[:user_1], params[:user_2])
    render json: conv.to_json

  end

  def conversation_messages
    check_admin
    conversation_sid = params[:conversation_sid]

    client = Twilio::REST::Client.new(
      ENV['TWILIO_ACCOUNT_SID'],
      ENV['TWILIO_AUTH_TOKEN']
    )

    messages = client.conversations
                     .conversations(conversation_sid)
                     .messages
                     .list(limit: 100)

    render json: messages.map { |msg|
      {
        sid: msg.sid,
        author: msg.author,
        body: msg.body,
        date_created: msg.date_created
      }
    }
  end
end
