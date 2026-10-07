class SubscriptionConsumableRegeneration
  def self.weekly(now: Time.current)
    eligible_users(now).select(:id).find_each do |user|
      eligible_users(now).where(id: user.id)
        .where('last_weekly_super_sweet_given IS NULL OR last_weekly_super_sweet_given < ?', now.beginning_of_week(:monday))
        .update_all(['superlike_available = GREATEST(COALESCE(superlike_available, 0), 5), last_weekly_super_sweet_given = ?, updated_at = GREATEST(COALESCE(updated_at, ?), ?)', now, now, now])
    end
  end

  def self.monthly(now: Time.current)
    eligible_users(now).select(:id).find_each do |user|
      eligible_users(now).where(id: user.id)
        .where('last_monthly_boost_given IS NULL OR last_monthly_boost_given < ?', now.beginning_of_month)
        .update_all(['boost_available = COALESCE(boost_available, 0) + 1, last_monthly_boost_given = ?, updated_at = GREATEST(COALESCE(updated_at, ?), ?)', now, now, now])
    end
  end

  # Keep legacy subscriptions with no recorded expiry eligible, but never
  # grant to subscriptions already known to have expired. Eligibility, period
  # and balance are evaluated by the same write after MySQL acquires its lock.
  # Each write targets one primary key, avoiding subscription-index range
  # locks that can deadlock concurrent subscription changes.
  def self.eligible_users(now)
    User.where(current_subscription_name: %w[premium supreme])
        .where('current_subscription_expires IS NULL OR current_subscription_expires > ?', now)
  end
  private_class_method :eligible_users
end
