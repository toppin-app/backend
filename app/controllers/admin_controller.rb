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

    begin
      messages = client.conversations
                       .conversations(conversation_sid)
                       .messages
                       .list(limit: 100)

      render json: messages.map { |msg|
        # Intenta buscar el usuario por identity (si lo usas así en Twilio)
        user = User.find_by(id: msg.author) || User.find_by(user_name: msg.author)
        {
          sid: msg.sid,
          author: user&.name || msg.author, # Muestra el nombre si lo encuentra, si no, el author original
          body: msg.body,
          date_created: msg.date_created
        }
      }
    rescue Twilio::REST::RestError => e
      render json: { error: "No se pudo cargar la conversación. Puede que no exista o haya sido eliminada." }, status: :not_found
    end
  end

  private

  def set_match_message_counts
    @match_message_counts = {}
    @matches.each do |match|
      if match.twilio_conversation_sid.present?
        begin
          client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
          count = client.conversations.conversations(match.twilio_conversation_sid).messages.list.count
          @match_message_counts[match.twilio_conversation_sid] = count
        rescue
          @match_message_counts[match.twilio_conversation_sid] = 0
        end
      end
    end
  end
end
