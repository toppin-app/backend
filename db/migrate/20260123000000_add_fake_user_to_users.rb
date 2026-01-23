class AddFakeUserToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :fake_user, :boolean, default: false, null: false
    
    # Marcar como fake_user a todos los usuarios que tengan @toppin o .toppin@ en el email
    reversible do |dir|
      dir.up do
        execute "UPDATE users SET fake_user = true WHERE email LIKE '%@toppin%' OR email LIKE '%.toppin@%'"
      end
    end
  end
end
