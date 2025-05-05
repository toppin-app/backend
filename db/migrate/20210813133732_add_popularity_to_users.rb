class AddPopularityToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :popularity, :integer
  end
end
