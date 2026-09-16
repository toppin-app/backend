class StripeConsumableCredit
  def self.call(payment_id:, user:, product_key:, config:)
    # Missing records remain retryable (the checkout transaction may still be
    # committing). Never acknowledge a credit without a durable receipt.
    raise ArgumentError, 'Stripe customer has no local user' unless user

    # Lock the owner rather than one purchase row: historical duplicate rows
    # with the same payment_id must not allow two workers to credit separately.
    user.with_lock do
      purchases = PurchasesStripe.where(payment_id: payment_id).to_a
      raise ActiveRecord::RecordNotFound, 'Stripe purchase not found' if purchases.empty?

      unless purchases.all? { |purchase| purchase.user_id == user.id && purchase.product_key == product_key }
        raise ArgumentError, 'Stripe purchase does not match its owner or product'
      end

      unless purchases.any? { |purchase| purchase.status == 'succeeded' }
        user.increment!(config[:field], config[:increment_value]) if config[:field] && config[:increment_value]
      end
      purchases.each { |purchase| purchase.update!(status: 'succeeded') unless purchase.status == 'succeeded' }
    end
  end
end
