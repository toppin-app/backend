class AddMatchesNumberToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :matches_number, :integer, default: 0
  end
end
