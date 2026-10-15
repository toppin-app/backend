require 'digest'

class PasswordRecoveryReset
  Result = Struct.new(:status, :body)

  def self.call(email:, new_password:, recovery_token: nil, code: nil)
    new(email: email, new_password: new_password, recovery_token: recovery_token, code: code).call
  end

  def initialize(email:, new_password:, recovery_token:, code:)
    @email = email.downcase
    @new_password = new_password
    @token = recovery_token
    @code = code
  end

  def call
    # Re-registration may leave an older deleted account with the same email.
    # Prefer the active account, while preserving the deleted-only rejection.
    user = User.find_by(email: @email, deleted_account: false) ||
           User.find_by(email: @email, deleted_account: true)
    return forbidden unless user

    user.with_lock do
      # All three HTTP recovery actions lock account then recovery rows.
      recoveries = PasswordRecovery.for_email(@email).order(:id).lock.to_a
      recovery = recoveries.max_by { |record| [record.created_at, record.id] }
      unless recovery&.verified? && !recovery.expired?
        next forbidden
      end
      if user.deleted_account?
        next Result.new(404, { status: 404, error: I18n.t('password_recoveries.errors.user_not_found') })
      end
      next forbidden if @token.nil? && @code.blank?
      next forbidden if recovery.reset_attempts >= PasswordRecovery::MAX_RESET_ATTEMPTS

      unless valid_proof?(recovery)
        recovery.update!(reset_attempts: recovery.reset_attempts + 1, last_attempt_at: Time.current)
        next forbidden
      end

      user.password = @new_password
      user.password_confirmation = @new_password
      unless user.save
        next Result.new(400, { status: 400, error: user.errors.full_messages.join(', ') })
      end
      # A failure to consume any old capability rolls the password change back.
      recoveries.each(&:destroy!)
      Result.new(200, { status: 200, message: I18n.t('password_recoveries.success.password_reset'), email: @email })
    end
  end

  private

  def valid_proof?(recovery)
    if !@token.nil?
      @token.is_a?(String) && recovery.reset_token_digest.present? &&
        ActiveSupport::SecurityUtils.secure_compare(recovery.reset_token_digest, Digest::SHA256.hexdigest(@token))
    else
      @code.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(recovery.recovery_code, @code)
    end
  end

  def forbidden
    Result.new(403, { status: 403, error: I18n.t('password_recoveries.errors.not_verified'), code: 'NOT_VERIFIED' })
  end
end
