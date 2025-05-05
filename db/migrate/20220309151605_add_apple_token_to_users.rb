class AddAppleTokenToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :apple_token, :string
  end
end
