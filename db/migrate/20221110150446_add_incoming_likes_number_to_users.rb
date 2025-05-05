class AddIncomingLikesNumberToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :incoming_likes_number, :integer, default: 0
  end
end
