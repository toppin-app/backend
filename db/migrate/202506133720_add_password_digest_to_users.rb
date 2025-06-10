class AddPasswordDigestToUsers < ActiveRecord::Migration[6.0] # El número de versión puede variar (e.g., 6.0, 7.0, 7.1, etc.)
  def change
    add_column :users, :password_digest, :string
  end
end