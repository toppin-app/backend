class Admin::MailerTestController < ApplicationController
  before_action :authenticate_user!
  before_action :check_admin
  
  def index
    @title = "Test de Emails - Mailjet"
    
    # Verificar configuración
    @config_status = {
      api_key: ENV['MAILJET_API_KEY'].present?,
      secret_key: ENV['MAILJET_SECRET_KEY'].present?,
      from_email: ENV['MAILJET_FROM_EMAIL'].present?,
      from_name: ENV['MAILJET_FROM_NAME'].present?,
      default_host: ENV['MAILJET_DEFAULT_URL_HOST'].present?
    }
    
    # Obtener últimos logs de emails (si existen)
    @recent_logs = session[:email_logs] || []
  end
  
  def send_test_email
    begin
      recipient = params[:email]
      email_type = params[:email_type] || 'test' # 'test' o 'welcome'
      
      if recipient.blank?
        render json: { 
          success: false, 
          error: "Debes proporcionar un email de destinatario" 
        }, status: :unprocessable_entity
        return
      end
      
      # Enviar email según el tipo
      case email_type
      when 'welcome'
        # Email de bienvenida
        temp_user = User.new(
          name: params[:name] || "Usuario de Prueba",
          email: recipient,
          user_name: (params[:name] || "Usuario de Prueba").downcase.gsub(' ', '')
        )
        result = WelcomeMailer.welcome_email(temp_user).deliver_now
        subject = "¡Bienvenido a Toppin! 🍩"
        email_description = "Email de Bienvenida"
        
      when 'test'
        # Email de prueba simple
        subject = params[:subject] || "Email de prueba desde Toppin"
        message = params[:message] || "Este es un email de prueba del panel de administración."
        result = TestMailer.notification_email(recipient, subject, message).deliver_now
        email_description = "Email de Prueba Simple"
        
      else
        render json: { 
          success: false, 
          error: "Tipo de email no válido: #{email_type}" 
        }, status: :unprocessable_entity
        return
      end
      
      # Guardar log en sesión
      log_entry = {
        timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
        to: recipient,
        subject: subject,
        email_type: email_description,
        status: "success",
        message: "Email enviado exitosamente"
      }
      
      session[:email_logs] ||= []
      session[:email_logs].unshift(log_entry)
      session[:email_logs] = session[:email_logs].take(20) # Mantener solo los últimos 20
      
      render json: { 
        success: true, 
        message: "#{email_description} enviado exitosamente a #{recipient}",
        log: log_entry
      }
      
    rescue StandardError => e
      Rails.logger.error "Error enviando email de prueba: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      log_entry = {
        timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
        to: recipient || "N/A",
        subject: subject || "N/A",
        email_type: email_type == 'welcome' ? "Email de Bienvenida" : "Email de Prueba Simple",
        status: "error",
        message: e.message
      }
      
      session[:email_logs] ||= []
      session[:email_logs].unshift(log_entry)
      session[:email_logs] = session[:email_logs].take(20)
      
      render json: { 
        success: false, 
        error: e.message,
        log: log_entry
      }, status: :internal_server_error
    end
  end
  
  def clear_logs
    session[:email_logs] = []
    render json: { success: true, message: "Logs limpiados" }
  end
  
  def check_config
    config = {
      api_key: {
        present: ENV['MAILJET_API_KEY'].present?,
        value: ENV['MAILJET_API_KEY'].present? ? "Configurado (#{ENV['MAILJET_API_KEY'][0..10]}...)" : "No configurado"
      },
      secret_key: {
        present: ENV['MAILJET_SECRET_KEY'].present?,
        value: ENV['MAILJET_SECRET_KEY'].present? ? "Configurado (#{ENV['MAILJET_SECRET_KEY'][0..10]}...)" : "No configurado"
      },
      from_email: {
        present: ENV['MAILJET_FROM_EMAIL'].present?,
        value: ENV['MAILJET_FROM_EMAIL'] || "No configurado"
      },
      from_name: {
        present: ENV['MAILJET_FROM_NAME'].present?,
        value: ENV['MAILJET_FROM_NAME'] || "No configurado"
      },
      default_host: {
        present: ENV['MAILJET_DEFAULT_URL_HOST'].present?,
        value: ENV['MAILJET_DEFAULT_URL_HOST'] || "No configurado"
      },
      delivery_method: ActionMailer::Base.delivery_method.to_s,
      rails_env: Rails.env
    }
    
    render json: { success: true, config: config }
  end
  
  private
  
  def check_admin
    unless current_user&.admin?
      redirect_to root_path, alert: "No tienes permisos para acceder a esta sección"
    end
  end
end
