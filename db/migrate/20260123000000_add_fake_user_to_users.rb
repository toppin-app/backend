class AddFakeUserToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :fake_user, :boolean, default: false, null: false
    
    # Marcar como fake_user a todos los usuarios que tengan @toppin o .toppin@ en el email
    reversible do |dir|
      dir.up do
        User.where("email LIKE '%@toppin%' OR email LIKE '%.toppin@%'").update_all(fake_user: true)
      end
    end
  end
end
