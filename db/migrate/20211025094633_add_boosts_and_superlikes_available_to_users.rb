class AddBoostsAndSuperlikesAvailableToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :boost_available, :integer, default: 0
    add_column :users, :superlike_available, :integer, default: 1
    add_column :users, :current_subscription_name, :string
    add_column :users, :current_subscription_expires, :datetime
  end
end
