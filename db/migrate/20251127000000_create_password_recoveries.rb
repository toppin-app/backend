class CreatePasswordRecoveries < ActiveRecord::Migration[6.0]
  def change
    create_table :password_recoveries do |t|
      t.string :email, null: false
      t.string :recovery_code, null: false
      t.boolean :verified, default: false
      t.datetime :expires_at, null: false
      t.integer :attempts, default: 0
      t.datetime :last_attempt_at

      t.timestamps
    end

    add_index :password_recoveries, :email
    add_index :password_recoveries, [:email, :verified]
  end
end
