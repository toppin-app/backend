class AddProfileCompletedToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :profile_completed, :integer, default: 10
  end
end
