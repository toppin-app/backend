class RenamePasswordDigestToEncryptedPassword < ActiveRecord::Migration[6.0]
  def change
    rename_column :users, :password_digest, :encrypted_password
  end
end