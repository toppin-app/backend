class AddCurrentSubscriptionIdToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :current_subscription_id, :string
  end
end
