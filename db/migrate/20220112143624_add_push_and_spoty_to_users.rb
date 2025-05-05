class AddPushAndSpotyToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :spoty1, :string
    add_column :users, :spoty2, :string
    add_column :users, :spoty3, :string
    add_column :users, :spoty4, :string
    add_column :users, :push_general, :boolean, default: true
    add_column :users, :push_match, :boolean, default: true
    add_column :users, :push_chat, :boolean, default: true
    add_column :users, :push_likes, :boolean, default: true
  end
end
