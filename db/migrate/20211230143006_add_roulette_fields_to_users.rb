class AddRouletteFieldsToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :spin_roulette_available, :integer, default: 1
    add_column :users, :last_roulette_played, :datetime
  end
end
