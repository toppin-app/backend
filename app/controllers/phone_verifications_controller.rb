class PhoneVerificationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:request_code, :verify_code]
  skip_before_action :verify_authenticity_token, only: [:request_code, :verify_code]
  before_action :set_locale

  # POST /phone_verifications/request_code
  # Params: { phone_number: "+34612345678", language: "ES" }
  def request_code
    phone_number = params[:phone_number]

    # Validar que se envió el teléfono
    unless phone_number.present?
      render json: { status: 400, error: t('phone_verifications.errors.phone_required') }, status: :bad_request
      return
    end

    # Validar formato básico del teléfono (debe empezar con +)
    unless phone_number.match?(/^\+\d{10,15}$/)
      render json: { status: 400, error: t('phone_verifications.errors.invalid_format') }, status: :bad_request
      return
    end

    # Verificar si el número de teléfono ya está registrado por otro usuario activo (no eliminado)
    existing_user = User.find_by(phone: phone_number, deleted_account: false)
    if existing_user
      render json: { 
        status: 409, 
        error: t('phone_verifications.errors.already_exists'),
        code: 'PHONE_ALREADY_EXISTS'
      }, status: :conflict
      return
    end

    # Verificar cooldown
    unless PhoneVerification.can_request_new_code?(phone_number)
      remaining_seconds = PhoneVerification.cooldown_remaining(phone_number)
      render json: { 
        status: 429, 
        error: t('phone_verifications.errors.cooldown', seconds: remaining_seconds)
      }, status: :too_many_requests
      return
    end

    begin
      # Crear nueva verificación
      verification = PhoneVerification.create_for_phone(phone_number)

      # Enviar SMS con Twilio (comentado temporalmente para desarrollo)
      Rails.logger.info "⚠️ SMS desactivado - Código de verificación: #{verification.verification_code}"

      render json: {
        status: 200,
        message: t('phone_verifications.success.code_sent'),
        expires_in: PhoneVerification::CODE_EXPIRATION_TIME.to_i,
        phone_number: phone_number,
        code: verification.verification_code
      }, status: :ok

    rescue StandardError => e
      Rails.logger.error "Error al enviar código de verificación: #{e.message}"
      render json: { 
        status: 500, 
        error: t('phone_verifications.errors.send_error')
      }, status: :internal_server_error
    end
  end

  # POST /phone_verifications/verify_code
  # Params: { phone_number: "+34612345678", code: "123456", language: "ES" }
  def verify_code
    phone_number = params[:phone_number]
    code = params[:code]

    # Validaciones
    unless phone_number.present? && code.present?
      render json: { status: 400, error: t('phone_verifications.errors.phone_and_code_required') }, status: :bad_request
      return
    end

    # Verificar si el número de teléfono ya está registrado por otro usuario activo (no eliminado)
    existing_user = User.find_by(phone: phone_number, deleted_account: false)
    if existing_user
      render json: { 
        status: 409, 
        error: t('phone_verifications.errors.already_exists'),
        code: 'PHONE_ALREADY_EXISTS'
      }, status: :conflict
      return
    end

    # Buscar la verificación más reciente y válida para este teléfono
    verification = PhoneVerification.for_phone(phone_number)
                                   .where(verified: false)
                                   .order(created_at: :desc)
                                   .first

    unless verification
      render json: { 
        status: 404, 
        error: t('phone_verifications.errors.no_pending_verification')
      }, status: :not_found
      return
    end

    # Verificar el código
    result = verification.verify_code(code)

    if result[:success]
      render json: {
        status: 200,
        message: t('phone_verifications.success.phone_verified'),
        phone_number: phone_number,
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

  # GET /phone_verifications/check_status
  # Params: { phone_number: "+34612345678" }
  def check_status
    phone_number = params[:phone_number]

    unless phone_number.present?
      render json: { status: 400, error: 'El número de teléfono es requerido' }, status: :bad_request
      return
    end

    # Buscar verificación válida
    verification = PhoneVerification.for_phone(phone_number)
                                   .where(verified: true)
                                   .order(created_at: :desc)
                                   .first

    if verification
      render json: {
        status: 200,
        verified: true,
        verified_at: verification.updated_at,
        phone_number: phone_number
      }, status: :ok
    else
      render json: {
        status: 200,
        verified: false,
        phone_number: phone_number
      }, status: :ok
    end
  end

  private

  # Establecer el idioma basado en el parámetro language del request
  def set_locale
    language = params[:language]&.upcase
    
    # Mapear el código del idioma a locale de Rails
    locale = case language
             when 'ES' then :es
             when 'EN' then :en
             when 'IT' then :it
             when 'FR' then :fr
             when 'DE' then :de
             else :es # Por defecto español
             end
    
    I18n.locale = locale
  end

  # Enviar SMS usando Twilio
  def send_verification_sms(phone_number, code)
    set_account
    
    message_body = "Tu código de verificación de Toppin es: #{code}. Válido por 10 minutos."
    
    @client.messages.create(
      from: '+19362152768',
      to: phone_number,
      body: message_body
    )
    
    Rails.logger.info "SMS enviado a #{phone_number}"
  rescue Twilio::REST::RestError => e
    Rails.logger.error "Error de Twilio: #{e.message}"
    raise e
  end

  def set_account
    @account_sid = ENV['TWILIO_ACCOUNT_SID']
    auth_token = ENV['TWILIO_AUTH_TOKEN']

    @api_key = ENV['TWILIO_API_KEY']
    @api_secret = ENV['TWILIO_API_SECRET']

    @service_sid = ENV['TWILIO_SERVICE_SID']

    @client = Twilio::REST::Client.new(@account_sid, auth_token)
  end
end
