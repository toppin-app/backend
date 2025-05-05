class AddLikesLeftToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :likes_left, :integer, default: 50
  end
end
