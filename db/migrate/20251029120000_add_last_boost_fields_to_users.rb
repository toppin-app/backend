class AddLastBoostFieldsToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :last_boost_started_at, :datetime
    add_column :users, :last_boost_ended_at, :datetime
  end
end
