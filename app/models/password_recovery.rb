class PasswordRecovery < ApplicationRecord
  # Validaciones
  validates :email, presence: true
  validates :recovery_code, presence: true
  validates :expires_at, presence: true

  # Constantes
  CODE_EXPIRATION_TIME = 10.minutes
  MAX_ATTEMPTS = 5
  COOLDOWN_PERIOD = 1.minute

  # Scopes
  scope :valid_codes, -> { where(verified: false).where('expires_at > ?', Time.current) }
  scope :for_email, ->(email) { where(email: email.downcase) }

  # Generar código de recuperación de 6 dígitos
  def self.generate_code
    rand(100000..999999).to_s
  end

  # Crear nueva recuperación para un email
  def self.create_for_email(email)
    code = generate_code
    expires_at = CODE_EXPIRATION_TIME.from_now

    create!(
      email: email.downcase,
      recovery_code: code,
      expires_at: expires_at,
      verified: false,
      attempts: 0
    )
  end

  # Verificar si el código es correcto
  def verify_code(input_code)
    # Verificar si ha expirado
    if expired?
      return { success: false, error: I18n.t('password_recoveries.errors.code_expired') }
    end

    # Verificar si se excedieron los intentos
    if max_attempts_reached?
      return { success: false, error: I18n.t('password_recoveries.errors.max_attempts') }
    end

    # Incrementar intentos
    increment!(:attempts)
    update(last_attempt_at: Time.current)

    # Verificar el código
    if recovery_code == input_code
      update(verified: true)
      { success: true, message: I18n.t('password_recoveries.success.code_verified') }
    else
      remaining = MAX_ATTEMPTS - attempts
      { success: false, error: I18n.t('password_recoveries.errors.incorrect_code', remaining: remaining) }
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
  def self.can_request_new_code?(email)
    last_recovery = for_email(email).order(created_at: :desc).first
    return true unless last_recovery

    # Permitir nuevo código si pasó el cooldown
    last_recovery.created_at < COOLDOWN_PERIOD.ago
  end

  # Obtener tiempo restante de cooldown
  def self.cooldown_remaining(email)
    last_recovery = for_email(email).order(created_at: :desc).first
    return 0 unless last_recovery

    remaining = COOLDOWN_PERIOD - (Time.current - last_recovery.created_at)
    [remaining.to_i, 0].max
  end

  # Limpiar recuperaciones antiguas (para llamar manualmente si es necesario)
  def self.cleanup_old_recoveries(days_old = 7)
    where('created_at < ?', days_old.days.ago).delete_all
  end
end
