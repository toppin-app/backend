class AddOpenedAtToBannerUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :banner_users, :opened_at, :datetime, null: true
    add_index :banner_users, :opened_at
  end
end
