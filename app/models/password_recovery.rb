require 'digest'
require 'securerandom'

class PasswordRecovery < ApplicationRecord
  # Validaciones
  validates :email, presence: true
  validates :recovery_code, presence: true
  validates :expires_at, presence: true

  # Constantes
  CODE_EXPIRATION_TIME = 10.minutes
  MAX_ATTEMPTS = 5
  MAX_RESET_ATTEMPTS = 5
  COOLDOWN_PERIOD = 1.minute

  # Scopes
  scope :valid_codes, -> { where(verified: false).where('expires_at > ?', Time.current) }
  scope :for_email, ->(email) { where(email: email.downcase) }

  # Generar código de recuperación de 6 dígitos
  def self.generate_code
    (100_000 + SecureRandom.random_number(900_000)).to_s
  end

  # Crear nueva recuperación para un email
  def self.create_for_email(email)
    code = generate_code
    expires_at = CODE_EXPIRATION_TIME.from_now

    transaction do
      # The HTTP request holds the account lock before replacing a capability.
      for_email(email).update_all(expires_at: Time.current, reset_token_digest: nil)
      create!(email: email.downcase, recovery_code: code, expires_at: expires_at,
              verified: false, attempts: 0)
    end
  end

  # Verificar si el código es correcto
  def verify_code(input_code)
    with_lock do
      if verified?
        next({ success: false, error: I18n.t('password_recoveries.errors.no_pending_recovery') })
      end
      if expired?
        next({ success: false, error: I18n.t('password_recoveries.errors.code_expired') })
      end
      if max_attempts_reached?
        next({ success: false, error: I18n.t('password_recoveries.errors.max_attempts') })
      end

      self.attempts = attempts.to_i + 1
      self.last_attempt_at = Time.current
      token = nil
      if input_code.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(recovery_code, input_code)
        token = SecureRandom.urlsafe_base64(32)
        self.verified = true
        self.reset_token_digest = Digest::SHA256.hexdigest(token)
      end
      save!

      if token
        { success: true, message: I18n.t('password_recoveries.success.code_verified'), recovery_token: token }
      else
        { success: false, error: I18n.t('password_recoveries.errors.incorrect_code', remaining: MAX_ATTEMPTS - attempts) }
      end
    end
  end

  # Verificar si el código ha expirado
  def expired?
    expires_at <= Time.current
  end

  # Verificar si se alcanzó el máximo de intentos
  def max_attempts_reached?
    attempts.to_i >= MAX_ATTEMPTS
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
