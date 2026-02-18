class AddOpenedAtToUsersPublis < ActiveRecord::Migration[6.0]
  def change
    add_column :users_publis, :opened_at, :datetime, null: true
    add_index :users_publis, :opened_at
  end
end
