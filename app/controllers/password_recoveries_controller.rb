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
    logo_url = "https://#{ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'}/logo-html.png"
    
    <<-HTML
      <!DOCTYPE html>
      <html lang="#{I18n.locale}">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{I18n.t('password_recoveries.email.subject')}</title>
        <style>
          body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background-color: #f5f5f5;
          }
          .email-container {
            max-width: 600px;
            margin: 0 auto;
            background-color: #ffffff;
          }
          .header {
            background: #FFFFFF;
            padding: 40px 20px;
            text-align: center;
            border-bottom: 3px solid #FF6B9D;
          }
          .logo {
            width: 120px;
            height: 120px;
            margin: 0 auto 20px;
            background: linear-gradient(135deg, #FF6B9D 0%, #C239B3 100%);
            border-radius: 60px;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 4px 15px rgba(255, 107, 157, 0.3);
            overflow: hidden;
          }
          .logo img {
            width: 100%;
            height: 100%;
            object-fit: cover;
          }
          .header h1 {
            color: #FF6B9D;
            margin: 0;
            font-size: 28px;
            font-weight: 700;
          }
          .content {
            padding: 40px 30px;
            color: #333333;
            line-height: 1.6;
          }
          .greeting {
            font-size: 20px;
            font-weight: 600;
            color: #333333;
            margin-bottom: 20px;
          }
          .message {
            font-size: 16px;
            color: #555555;
            margin-bottom: 30px;
          }
          .code-box {
            background: linear-gradient(135deg, #FFF5F8 0%, #FFE8F0 100%);
            border: 3px solid #FF6B9D;
            border-radius: 16px;
            padding: 30px;
            text-align: center;
            margin: 30px 0;
            box-shadow: 0 4px 15px rgba(255, 107, 157, 0.1);
          }
          .code-label {
            font-size: 14px;
            color: #999999;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
            font-weight: 600;
          }
          .code {
            font-size: 42px;
            font-weight: 800;
            color: #FF6B9D;
            letter-spacing: 8px;
            margin: 15px 0;
            font-family: 'Courier New', monospace;
            text-shadow: 2px 2px 4px rgba(255, 107, 157, 0.2);
          }
          .validity-warning {
            background-color: #FFF5F8;
            border-left: 4px solid #FF6B9D;
            padding: 15px 20px;
            margin: 25px 0;
            border-radius: 8px;
          }
          .validity-warning p {
            margin: 0;
            color: #666666;
            font-size: 15px;
          }
          .validity-warning strong {
            color: #FF6B9D;
            font-weight: 600;
          }
          .security-note {
            background-color: #F8F8F8;
            border-radius: 12px;
            padding: 20px;
            margin-top: 30px;
            font-size: 14px;
            color: #666666;
            text-align: center;
          }
          .security-note .icon {
            font-size: 32px;
            margin-bottom: 10px;
          }
          .footer {
            background-color: #F8F8F8;
            padding: 30px;
            text-align: center;
            color: #999999;
            font-size: 13px;
            border-top: 1px solid #EEEEEE;
          }
          .footer a {
            color: #FF6B9D;
            text-decoration: none;
          }
          @media only screen and (max-width: 600px) {
            .content {
              padding: 30px 20px;
            }
            .code {
              font-size: 36px;
              letter-spacing: 6px;
            }
            .header h1 {
              font-size: 24px;
            }
          }
        </style>
      </head>
      <body>
        <div class="email-container">
          <!-- Header con logo -->
          <div class="header">
            <div class="logo">
              <img src="#{logo_url}" alt="Toppin Logo">
            </div>
            <h1>🔐 #{I18n.t('password_recoveries.email.subject')}</h1>
          </div>

          <!-- Contenido principal -->
          <div class="content">
            <p class="greeting">#{vars['greeting']} #{vars['name']},</p>
            
            <p class="message">#{vars['message']}</p>

            <!-- Caja del código -->
            <div class="code-box">
              <div class="code-label">#{I18n.t('password_recoveries.email.your_code')}</div>
              <div class="code">#{vars['code']}</div>
            </div>

            <!-- Advertencia de validez -->
            <div class="validity-warning">
              <p><strong>⏰ #{vars['validity']}</strong></p>
            </div>

            <!-- Nota de seguridad -->
            <div class="security-note">
              <div class="icon">🔒</div>
              <p>#{vars['footer']}</p>
            </div>
          </div>

          <!-- Footer -->
          <div class="footer">
            <p>
              © #{Time.current.year} Toppin. Todos los derechos reservados.<br>
              Este es un correo automático, por favor no respondas a este mensaje.
            </p>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end
