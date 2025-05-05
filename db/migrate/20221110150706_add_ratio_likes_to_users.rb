class AddRatioLikesToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :ratio_likes, :float, default: 0
  end
end
