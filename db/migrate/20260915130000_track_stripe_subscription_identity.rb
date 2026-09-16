class TrackStripeSubscriptionIdentity < ActiveRecord::Migration[6.0]
  def change
    # Separate from current_subscription_id, which stores legacy product identifiers.
    # Keep these after cancellation to reject late events from older subscriptions.
    add_column :users, :stripe_subscription_id, :string
    add_column :users, :stripe_subscription_created_at, :bigint
  end
end
