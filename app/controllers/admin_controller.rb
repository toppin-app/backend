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

  def metrics_active_users
    check_admin
    @title = "Usuarios Activos - Detalle"
    
    # Datos para los últimos 30 días
    @daily_data = (0..29).map do |days_ago|
      date = days_ago.days.ago.to_date
      count = User.where('DATE(last_sign_in_at) = ?', date).count
      {
        date: date.strftime('%d/%m'),
        count: count
      }
    end.reverse
    
    # Datos por hora del día de hoy
    @hourly_data = (0..23).map do |hour|
      start_time = Time.current.beginning_of_day + hour.hours
      end_time = start_time + 1.hour
      count = User.where(last_sign_in_at: start_time..end_time).count
      {
        hour: "#{hour}:00",
        count: count
      }
    end
    
    # Total de usuarios registrados
    @total_users = User.count
    @users_today = User.where('last_sign_in_at >= ?', 24.hours.ago).count
    @users_week = User.where('last_sign_in_at >= ?', 7.days.ago).count
    @users_month = User.where('last_sign_in_at >= ?', 30.days.ago).count
  end

  def metrics_matches
    check_admin
    @title = "Matches - Detalle"
    
    # Matches por día (últimos 30 días)
    @daily_matches = (0..29).map do |days_ago|
      date = days_ago.days.ago.to_date
      count = UserMatchRequest.where(is_match: true).where('DATE(match_date) = ?', date).count
      {
        date: date.strftime('%d/%m'),
        count: count
      }
    end.reverse
    
    # Comparativa mensual (últimos 6 meses)
    @monthly_matches = (0..5).map do |months_ago|
      start_date = months_ago.months.ago.beginning_of_month
      end_date = months_ago.months.ago.end_of_month
      count = UserMatchRequest.where(is_match: true).where(match_date: start_date..end_date).count
      {
        month: start_date.strftime('%b %Y'),
        count: count
      }
    end.reverse
    
    # Estadísticas adicionales
    @total_matches = UserMatchRequest.where(is_match: true).count
    @matches_today = UserMatchRequest.where(is_match: true).where('match_date >= ?', 24.hours.ago).count
    @matches_week = UserMatchRequest.where(is_match: true).where('match_date >= ?', 7.days.ago).count
    @average_daily = @total_matches > 0 ? (@total_matches.to_f / User.maximum(:id)).round(2) : 0
  end

  def metrics_retention
    check_admin
    @title = "Retención de Usuarios - Detalle"
    
    # Retención por cohortes (últimos 6 meses)
    @cohort_data = (1..6).map do |months_ago|
      # Usuarios registrados en ese mes
      start_date = months_ago.months.ago.beginning_of_month
      end_date = months_ago.months.ago.end_of_month
      
      registered = User.where(created_at: start_date..end_date).count
      
      # Cuántos siguen activos
      still_active = User.where(created_at: start_date..end_date)
                         .where('last_sign_in_at >= ?', 7.days.ago).count
      
      retention = registered > 0 ? ((still_active.to_f / registered) * 100).round(2) : 0
      
      {
        month: start_date.strftime('%b %Y'),
        registered: registered,
        retained: still_active,
        retention_rate: retention
      }
    end.reverse
    
    # Retención general
    @retention_data = calculate_retention_rate
    
    # Usuarios inactivos (no se han conectado en más de 30 días)
    @inactive_users = User.where('last_sign_in_at < ? OR last_sign_in_at IS NULL', 30.days.ago).count
    @total_users = User.count
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
    # Usuarios que se registraron hace entre 30 y 37 días (una semana de margen)
    # Esto nos da una muestra más amplia y estable
    users_registered = User.where('created_at >= ? AND created_at <= ?', 37.days.ago, 30.days.ago).count
    
    # De esos usuarios, cuántos siguen activos (se conectaron en los últimos 7 días)
    retained_users = User.where('created_at >= ? AND created_at <= ?', 37.days.ago, 30.days.ago)
                         .where('last_sign_in_at >= ?', 7.days.ago).count
    
    retention_rate = users_registered > 0 ? ((retained_users.to_f / users_registered) * 100).round(2) : 0
    
    {
      users_registered_30_days_ago: users_registered,
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
