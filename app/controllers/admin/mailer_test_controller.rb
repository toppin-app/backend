class Admin::MailerTestController < ApplicationController
  before_action :authenticate_user!
  before_action :check_admin
  
  def index
    @title = "Test de Emails - MailerSend"
    
    # Verificar configuración
    @config_status = {
      api_token: ENV['MAILERSEND_API_TOKEN'].present?,
      from_email: ENV['MAILERSEND_FROM_EMAIL'].present?,
      from_name: ENV['MAILERSEND_FROM_NAME'].present?,
      default_host: ENV['MAILERSEND_DEFAULT_URL_HOST'].present?
    }
    
    # Obtener últimos logs de emails (si existen)
    @recent_logs = session[:email_logs] || []
  end
  
  def send_test_email
    begin
      recipient = params[:email]
      subject = params[:subject] || "Email de prueba desde Toppin"
      message = params[:message] || "Este es un email de prueba del panel de administración."
      
      if recipient.blank?
        render json: { 
          success: false, 
          error: "Debes proporcionar un email de destinatario" 
        }, status: :unprocessable_entity
        return
      end
      
      # Enviar email
      result = TestMailer.notification_email(recipient, subject, message).deliver_now
      
      # Guardar log en sesión
      log_entry = {
        timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
        to: recipient,
        subject: subject,
        status: "success",
        message: "Email enviado exitosamente"
      }
      
      session[:email_logs] ||= []
      session[:email_logs].unshift(log_entry)
      session[:email_logs] = session[:email_logs].take(20) # Mantener solo los últimos 20
      
      render json: { 
        success: true, 
        message: "Email enviado exitosamente a #{recipient}",
        log: log_entry
      }
      
    rescue StandardError => e
      Rails.logger.error "Error enviando email de prueba: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      log_entry = {
        timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
        to: recipient || "N/A",
        subject: subject || "N/A",
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
      api_token: {
        present: ENV['MAILERSEND_API_TOKEN'].present?,
        value: ENV['MAILERSEND_API_TOKEN'].present? ? "Configurado (#{ENV['MAILERSEND_API_TOKEN'][0..10]}...)" : "No configurado"
      },
      from_email: {
        present: ENV['MAILERSEND_FROM_EMAIL'].present?,
        value: ENV['MAILERSEND_FROM_EMAIL'] || "No configurado"
      },
      from_name: {
        present: ENV['MAILERSEND_FROM_NAME'].present?,
        value: ENV['MAILERSEND_FROM_NAME'] || "No configurado"
      },
      default_host: {
        present: ENV['MAILERSEND_DEFAULT_URL_HOST'].present?,
        value: ENV['MAILERSEND_DEFAULT_URL_HOST'] || "No configurado"
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
