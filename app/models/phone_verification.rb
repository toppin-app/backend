class PhoneVerification < ApplicationRecord
  # Validaciones
  validates :phone_number, presence: true
  validates :verification_code, presence: true
  validates :expires_at, presence: true

  # Constantes
  CODE_EXPIRATION_TIME = 10.minutes
  MAX_ATTEMPTS = 5
  COOLDOWN_PERIOD = 1.minute

  # Scopes
  scope :valid_codes, -> { where(verified: false).where('expires_at > ?', Time.current) }
  scope :for_phone, ->(phone) { where(phone_number: phone) }

  # Generar código de verificación de 6 dígitos
  def self.generate_code
    rand(100000..999999).to_s
  end

  # Crear nueva verificación para un teléfono
  def self.create_for_phone(phone_number)
    code = generate_code
    expires_at = CODE_EXPIRATION_TIME.from_now

    create!(
      phone_number: phone_number,
      verification_code: code,
      expires_at: expires_at,
      verified: false,
      attempts: 0
    )
  end

  # Verificar si el código es correcto
  def verify_code(input_code)
    # Verificar si ha expirado
    if expired?
      return { success: false, error: I18n.t('phone_verifications.errors.code_expired') }
    end

    # Verificar si se excedieron los intentos
    if max_attempts_reached?
      return { success: false, error: I18n.t('phone_verifications.errors.max_attempts') }
    end

    # Incrementar intentos
    increment!(:attempts)
    update(last_attempt_at: Time.current)

    # Verificar el código
    if verification_code == input_code
      update(verified: true)
      { success: true, message: I18n.t('phone_verifications.success.phone_verified') }
    else
      remaining = MAX_ATTEMPTS - attempts
      { success: false, error: I18n.t('phone_verifications.errors.incorrect_code', remaining: remaining) }
    end
  end

  # Verificar si el código ha expirado
  def expired?
    expires_at < Time.current
  end

  # Verificar si se alcanzó el máximo de intentos
  def max_attempts_reached?
    attempts >= MAX_ATTEMPTS
  end

  # Verificar si puede solicitar un nuevo código (cooldown)
  def self.can_request_new_code?(phone_number)
    last_verification = for_phone(phone_number).order(created_at: :desc).first
    return true unless last_verification

    # Permitir nuevo código si pasó el cooldown
    last_verification.created_at < COOLDOWN_PERIOD.ago
  end

  # Obtener tiempo restante de cooldown
  def self.cooldown_remaining(phone_number)
    last_verification = for_phone(phone_number).order(created_at: :desc).first
    return 0 unless last_verification

    remaining = COOLDOWN_PERIOD - (Time.current - last_verification.created_at)
    [remaining.to_i, 0].max
  end

  # Limpiar verificaciones antiguas (para llamar manualmente si es necesario)
  def self.cleanup_old_verifications(days_old = 7)
    where('created_at < ?', days_old.days.ago).delete_all
  end
end
