class AddSpinNumberToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :spin_number, :integer, default: 0
  end
end