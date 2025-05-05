class CreateAppleTokens < ActiveRecord::Migration[6.0]
  def change
    create_table :apple_tokens do |t|
      t.string :token
      t.string :email

      t.timestamps
    end
  end
end
