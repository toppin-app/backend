class AddPrivateResetProofToPasswordRecoveries < ActiveRecord::Migration[6.0]
  def change
    add_column :password_recoveries, :reset_token_digest, :string
    add_column :password_recoveries, :reset_attempts, :integer, default: 0, null: false
  end
end
