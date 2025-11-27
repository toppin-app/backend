class PasswordRecoveriesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:request_code, :verify_code, :reset_password]
  skip_before_action :verify_authenticity_token, only: [:request_code, :verify_code, :reset_password]
  before_action :set_locale

  # POST /password_recoveries/request_code
  # Params: { email: "user@example.com", language: "ES" }
  def request_code
    email = params[:email]

    # Validar que se envió el email
    unless email.present?
      render json: { status: 400, error: t('password_recoveries.errors.email_required') }, status: :bad_request
      return
    end

    # Validar formato básico del email
    unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
      render json: { status: 400, error: t('password_recoveries.errors.invalid_format') }, status: :bad_request
      return
    end

    # Verificar si el usuario existe y no está eliminado
    user = User.find_by(email: email.downcase, deleted_account: false)
    unless user
      render json: { 
        status: 404, 
        error: t('password_recoveries.errors.user_not_found'),
        code: 'USER_NOT_FOUND'
      }, status: :not_found
      return
    end

    # Verificar cooldown
    unless PasswordRecovery.can_request_new_code?(email)
      remaining_seconds = PasswordRecovery.cooldown_remaining(email)
      render json: { 
        status: 429, 
        error: t('password_recoveries.errors.cooldown', seconds: remaining_seconds)
      }, status: :too_many_requests
      return
    end

    begin
      # Crear nueva recuperación
      recovery = PasswordRecovery.create_for_email(email)

      # Enviar email con el código usando Mailjet
      send_recovery_email(email, recovery.recovery_code, user.name)

      render json: {
        status: 200,
        message: t('password_recoveries.success.code_sent'),
        expires_in: PasswordRecovery::CODE_EXPIRATION_TIME.to_i,
        email: email
      }, status: :ok

    rescue StandardError => e
      Rails.logger.error "Error al enviar código de recuperación: #{e.message}"
      render json: { 
        status: 500, 
        error: t('password_recoveries.errors.send_error')
      }, status: :internal_server_error
    end
  end

  # POST /password_recoveries/verify_code
  # Params: { email: "user@example.com", code: "123456", language: "ES" }
  def verify_code
    email = params[:email]
    code = params[:code]

    # Validaciones
    unless email.present? && code.present?
      render json: { status: 400, error: t('password_recoveries.errors.email_and_code_required') }, status: :bad_request
      return
    end

    # Buscar la recuperación más reciente y válida para este email
    recovery = PasswordRecovery.for_email(email)
                               .where(verified: false)
                               .order(created_at: :desc)
                               .first

    unless recovery
      render json: { 
        status: 404, 
        error: t('password_recoveries.errors.no_pending_recovery')
      }, status: :not_found
      return
    end

    # Verificar el código
    result = recovery.verify_code(code)

    if result[:success]
      render json: {
        status: 200,
        message: result[:message],
        email: email,
        verified: true
      }, status: :ok
    else
      render json: {
        status: 400,
        error: result[:error],
        verified: false
      }, status: :bad_request
    end
  end

  # POST /password_recoveries/reset_password
  # Params: { email: "user@example.com", new_password: "NewPass123!", language: "ES" }
  def reset_password
    email = params[:email]
    new_password = params[:new_password]

    # Validaciones
    unless email.present? && new_password.present?
      render json: { 
        status: 400, 
        error: t('password_recoveries.errors.email_and_password_required') 
      }, status: :bad_request
      return
    end

    # Buscar la recuperación verificada más reciente
    recovery = PasswordRecovery.for_email(email)
                               .where(verified: true)
                               .where('expires_at > ?', Time.current)
                               .order(created_at: :desc)
                               .first

    unless recovery
      render json: { 
        status: 403, 
        error: t('password_recoveries.errors.not_verified'),
        code: 'NOT_VERIFIED'
      }, status: :forbidden
      return
    end

    # Buscar el usuario
    user = User.find_by(email: email.downcase, deleted_account: false)
    unless user
      render json: { 
        status: 404, 
        error: t('password_recoveries.errors.user_not_found')
      }, status: :not_found
      return
    end

    # Actualizar la contraseña
    begin
      user.password = new_password
      user.password_confirmation = new_password
      
      if user.save
        # Marcar la recuperación como usada eliminándola
        recovery.destroy

        render json: {
          status: 200,
          message: t('password_recoveries.success.password_reset'),
          email: email
        }, status: :ok
      else
        render json: {
          status: 400,
          error: user.errors.full_messages.join(', ')
        }, status: :bad_request
      end

    rescue StandardError => e
      Rails.logger.error "Error al resetear contraseña: #{e.message}"
      render json: { 
        status: 500, 
        error: t('password_recoveries.errors.reset_error')
      }, status: :internal_server_error
    end
  end

  private

  # Establecer el idioma basado en el parámetro language del request
  def set_locale
    language = params[:language]&.upcase
    
    locale = case language
             when 'ES' then :es
             when 'EN' then :en
             when 'IT' then :it
             when 'FR' then :fr
             when 'DE' then :de
             else :es
             end
    
    I18n.locale = locale
  end

  # Enviar email de recuperación usando Mailjet
  def send_recovery_email(email, code, user_name)
    # Configurar Mailjet primero
    Mailjet.configure do |config|
      config.api_key = ENV['MAILJET_API_KEY']
      config.secret_key = ENV['MAILJET_SECRET_KEY']
      config.api_version = 'v3.1'
    end

    # Obtener el template según el idioma
    subject = I18n.t('password_recoveries.email.subject')
    
    variables = {
      'name' => user_name || 'Usuario',
      'code' => code,
      'greeting' => I18n.t('password_recoveries.email.greeting'),
      'message' => I18n.t('password_recoveries.email.message'),
      'validity' => I18n.t('password_recoveries.email.validity'),
      'footer' => I18n.t('password_recoveries.email.footer')
    }

    message = {
      'From' => {
        'Email' => ENV['MAILJET_FROM_EMAIL'] || 'it@toppin.es',
        'Name' => ENV['MAILJET_FROM_NAME'] || 'Toppin'
      },
      'To' => [
        {
          'Email' => email,
          'Name' => user_name
        }
      ],
      'Subject' => subject,
      'TextPart' => "#{variables['greeting']} #{variables['name']},\n\n#{variables['message']}\n\nCódigo: #{code}\n\n#{variables['validity']}\n\n#{variables['footer']}",
      'HTMLPart' => generate_recovery_email_html(variables)
    }

    response = Mailjet::Send.create(messages: [message])

    Rails.logger.info "✓ Email de recuperación enviado a #{email} - Código: #{code}"
  rescue StandardError => e
    Rails.logger.error "✗ Error enviando email con Mailjet: #{e.message}"
    # Loguear el código para desarrollo
    Rails.logger.info "⚠️ Email no enviado (error de Mailjet) - Código de recuperación: #{code}"
    # Re-lanzar para que el controlador maneje el error
    raise e
  end

  # Generar HTML del email
  def generate_recovery_email_html(vars)
    <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .code-box { background: white; border: 2px dashed #667eea; border-radius: 8px; padding: 20px; text-align: center; margin: 20px 0; }
          .code { font-size: 32px; font-weight: bold; color: #667eea; letter-spacing: 5px; }
          .footer { text-align: center; color: #666; font-size: 12px; margin-top: 20px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🔐 Toppin</h1>
          </div>
          <div class="content">
            <p><strong>#{vars['greeting']} #{vars['name']},</strong></p>
            <p>#{vars['message']}</p>
            <div class="code-box">
              <p style="margin: 0; color: #666;">#{I18n.t('password_recoveries.email.your_code')}</p>
              <div class="code">#{vars['code']}</div>
            </div>
            <p><strong>⏰ #{vars['validity']}</strong></p>
            <p style="color: #666; font-size: 14px;">#{vars['footer']}</p>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
