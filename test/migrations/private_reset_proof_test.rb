require 'test_helper'
require Rails.root.join('db/migrate/20261015120000_add_private_reset_proof_to_password_recoveries')

class PrivateResetProofTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  setup do
    @migration = AddPrivateResetProofToPasswordRecoveries.new
    @recovery = PasswordRecovery.create!(email: "migration-#{SecureRandom.hex(6)}@example.com", recovery_code: '123456',
                                        expires_at: 10.minutes.from_now, verified: true, attempts: 4)
    @migration.migrate(:down)
    PasswordRecovery.reset_column_information
  end

  teardown do
    unless ActiveRecord::Base.connection.column_exists?(:password_recoveries, :reset_attempts)
      @migration.migrate(:up)
    end
    PasswordRecovery.reset_column_information
    PasswordRecovery.where(id: @recovery.id).delete_all
  end

  test 'proof migration preserves outstanding legacy verification and sets a separate zero budget' do
    @migration.migrate(:up)
    PasswordRecovery.reset_column_information
    recovery = @recovery.reload
    assert_equal '123456', recovery.recovery_code
    assert recovery.verified?
    assert_equal 4, recovery.attempts
    assert_equal 0, recovery.reset_attempts
    assert_nil recovery.reset_token_digest
    column = ActiveRecord::Base.connection.columns(:password_recoveries).find { |item| item.name == 'reset_attempts' }
    assert_not column.null
    assert_equal '0', column.default.to_s
  end

  test 'rollback removes only proof fields and leaves the legacy capability intact' do
    connection = ActiveRecord::Base.connection
    assert_not connection.column_exists?(:password_recoveries, :reset_token_digest)
    assert_not connection.column_exists?(:password_recoveries, :reset_attempts)
    assert_equal '123456', PasswordRecovery.find(@recovery.id).recovery_code
    assert PasswordRecovery.find(@recovery.id).verified?
    assert_equal 4, PasswordRecovery.find(@recovery.id).attempts
  end
end
