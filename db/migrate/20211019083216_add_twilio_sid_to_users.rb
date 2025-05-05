class AddTwilioSidToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :twilio_sid, :string
  end
end
