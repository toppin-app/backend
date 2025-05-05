class AddNextSugarPlayToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :next_sugar_play, :integer, default: 30
  end
end
