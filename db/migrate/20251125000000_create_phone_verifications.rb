class CreatePhoneVerifications < ActiveRecord::Migration[6.0]
  def change
    create_table :phone_verifications do |t|
      t.string :phone_number, null: false
      t.string :verification_code, null: false
      t.boolean :verified, default: false
      t.datetime :expires_at, null: false
      t.integer :attempts, default: 0
      t.datetime :last_attempt_at

      t.timestamps
    end

    add_index :phone_verifications, :phone_number
    add_index :phone_verifications, [:phone_number, :verified]
  end
end
