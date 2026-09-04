class StripeSubscriptionReplacement
  METADATA_KEY = "replaces_subscription_ids".freeze
  REPLACEABLE_STATUSES = %w[active trialing past_due unpaid paused].freeze
  ACCESS_STATUSES = %w[active trialing].freeze

  def self.active_subscription_ids(customer_id, subscriptions: Stripe::Subscription)
    subscriptions
      .list(customer: customer_id, status: "all", limit: 100)
      .data
      .select { |subscription| REPLACEABLE_STATUSES.include?(value(subscription, :status).to_s) }
      .map { |subscription| value(subscription, :id) }
      .compact
      .uniq
  end

  def self.metadata_for(subscription_ids)
    ids = Array(subscription_ids).compact.map(&:to_s).reject(&:empty?).uniq
    ids.empty? ? {} : { METADATA_KEY => ids.join(",") }
  end

  def self.cancel_replaced!(subscription, subscriptions: Stripe::Subscription)
    current_id = value(subscription, :id).to_s

    replaced_subscription_ids(subscription).each do |subscription_id|
      next if subscription_id == current_id

      previous_subscription = subscriptions.retrieve(subscription_id)
      status = value(previous_subscription, :status).to_s
      next unless REPLACEABLE_STATUSES.include?(status)

      subscriptions.cancel(subscription_id)
    end
  end

  def self.other_live_subscription?(customer_id, excluded_id, subscriptions: Stripe::Subscription)
    subscriptions
      .list(customer: customer_id, status: "all", limit: 100)
      .data
      .any? do |subscription|
        value(subscription, :id).to_s != excluded_id.to_s &&
          ACCESS_STATUSES.include?(value(subscription, :status).to_s)
      end
  end

  def self.replaced_subscription_ids(subscription)
    metadata = value(subscription, :metadata)
    raw_ids = value(metadata, METADATA_KEY)

    raw_ids.to_s.split(",").map(&:strip).reject(&:empty?).uniq
  end

  def self.value(object, key)
    return if object.nil?

    if object.respond_to?(key)
      object.public_send(key)
    elsif object.respond_to?(:[])
      object[key.to_s] || object[key.to_sym]
    end
  end
  private_class_method :value
end
