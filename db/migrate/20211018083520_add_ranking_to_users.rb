class AddRankingToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :ranking, :integer, default: 50
    add_column :users, :user_gen, :boolean, default: false
  end
end
