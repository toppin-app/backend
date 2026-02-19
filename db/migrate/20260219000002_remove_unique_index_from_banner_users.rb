class RemoveUniqueIndexFromBannerUsers < ActiveRecord::Migration[6.0]
  def change
    remove_index :banner_users, name: "index_banner_users_on_user_id_and_banner_id"
    add_index :banner_users, [:user_id, :banner_id]
  end
end
