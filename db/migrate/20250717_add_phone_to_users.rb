class AddPhoneToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :phone, :string
    add_column :users, :phone_verification_code, :string
    add_column :users, :phone_verification_sent_at, :datetime
  end
end