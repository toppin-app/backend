class AddBundledToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :bundled, :boolean, default: false
  end
end
