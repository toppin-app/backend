class AdminController < ApplicationController
  before_action :authenticate_user!
  
  def index
    check_admin
    @title = "Panel de control administración"
  end

  def metrics
    check_admin
    @title = "Métricas de Toppin"
    
    # Usuarios activos
    @active_users_today = User.where('last_sign_in_at >= ?', 24.hours.ago).count
    @active_users_week = User.where('last_sign_in_at >= ?', 7.days.ago).count
    @active_users_month = User.where('last_sign_in_at >= ?', 30.days.ago).count
    
    # Matches creados
    @matches_today = UserMatchRequest.where(is_match: true).where('match_date >= ?', 24.hours.ago).count
    @matches_week = UserMatchRequest.where(is_match: true).where('match_date >= ?', 7.days.ago).count
    @matches_this_month = UserMatchRequest.where(is_match: true).where('match_date >= ?', 30.days.ago).count
    @matches_last_month = UserMatchRequest.where(is_match: true).where('match_date >= ? AND match_date < ?', 60.days.ago, 30.days.ago).count
    
    # Tasa de retención
    @retention_data = calculate_retention_rate
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
        user = User.find_by(id: msg.author) || User.find_by(user_name: msg.author)
        {
          sid: msg.sid,
          author: user&.name || msg.author,
          author_id: user&.id || msg.author, # <-- Añade el id real del autor
          body: msg.body,
          date_created: msg.date_created
        }
      }
    rescue Twilio::REST::RestError => e
      render json: { error: "No se pudo cargar la conversación. Puede que no exista o haya sido eliminada." }, status: :not_found
    end
  end

  private
  
  def calculate_retention_rate
    # Usuarios que se registraron hace 30 días
    users_30_days_ago = User.where('created_at <= ? AND created_at >= ?', 30.days.ago, 31.days.ago).count
    
    # De esos usuarios, cuántos siguen activos (se conectaron en los últimos 7 días)
    retained_users = User.where('created_at <= ? AND created_at >= ?', 30.days.ago, 31.days.ago)
                         .where('last_sign_in_at >= ?', 7.days.ago).count
    
    retention_rate = users_30_days_ago > 0 ? ((retained_users.to_f / users_30_days_ago) * 100).round(2) : 0
    
    {
      users_registered_30_days_ago: users_30_days_ago,
      still_active: retained_users,
      retention_rate: retention_rate
    }
  end

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
