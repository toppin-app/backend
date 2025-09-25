class AddDeletedAccountToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :deleted_account, :boolean, default: false
    add_index :users, :deleted_account
  end
end