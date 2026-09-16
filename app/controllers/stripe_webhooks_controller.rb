class StripeWebhooksController < ApplicationController
  # Stripe recomienda desactivar CSRF para webhooks
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
    
  PRODUCT_CONFIG = {
    "toppin_sweet_A" => { field: :spin_roulette_available, increment_value: 5 },
    "toppin_sweet_B" => { field: :spin_roulette_available, increment_value: 10 },
    "toppin_sweet_C" => { field: :spin_roulette_available, increment_value: 20 },
    "power_sweet_A"    => { field: :boost_available, increment_value: 1 },
    "power_sweet_B"    => { field: :boost_available, increment_value: 5 },
    "power_sweet_C"    => { field: :boost_available, increment_value: 10 },
    "super_sweet_A"    => { field: :superlike_available, increment_value: 5 },
    "super_sweet_B"    => { field: :superlike_available, increment_value: 25 },
    "super_sweet_C"    => { field: :superlike_available, increment_value: 60 },
    "toppin_supreme_A" => { subscription_name: "supreme", months: 1 },
    "toppin_supreme_B" => { subscription_name: "supreme", months: 3 },
    "toppin_supreme_C" => { subscription_name: "supreme", months: 6 },
    "toppin_premium_A" => { subscription_name: "premium", months: 1 },
    "toppin_premium_B" => { subscription_name: "premium", months: 3 },
    "toppin_premium_C" => { subscription_name: "premium", months: 6 },
     "toppin_premium_AA" => { subscription_name: "premium", months: 12 }
    # Agrega más productos aquí
  }
  def receive
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']
    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      return head :bad_request
    end
    case event['type']
    when 'payment_intent.succeeded'
      payment_intent = event['data']['object']
      invoice_id = payment_intent['invoice']

      if invoice_id.present?
        finalize_paid_subscription(Stripe::Invoice.retrieve(invoice_id))
      else
        product_key = payment_intent.metadata['product_key'] rescue nil
        if product_key.nil? || product_key.to_s.empty?
          Rails.logger.error("Stripe Webhook: Missing product_key in payment_intent metadata for id #{payment_intent['id']}")
          return render json: { error: "Missing product key" }, status: :bad_request
        end
        config = PRODUCT_CONFIG[product_key]
        unless config
          Rails.logger.error("Stripe Webhook: Invalid product_key '#{product_key}' for payment_intent id #{payment_intent['id']}")
          return render json: { error: "Invalid product key" }, status: :bad_request
        end
        email = Stripe::Customer.retrieve(payment_intent['customer']).email
        user = User.find_by(email: email)
        StripeConsumableCredit.call(payment_id: payment_intent['id'], user: user,
                                   product_key: product_key, config: config)
      end
    when 'payment_intent.canceled'
      payment_intent = event['data']['object']
      purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
      update_unpaid_purchase(purchase, 'canceled')
    when 'payment_intent.payment_failed'
      payment_intent = event['data']['object']
      purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
      update_unpaid_purchase(purchase, 'failed')
    when 'invoice.paid'
      finalize_paid_subscription(event['data']['object'])
    when 'customer.subscription.created', 'customer.subscription.updated'
      subscription = event['data']['object']
      
      activate_subscription(subscription)
    when 'customer.subscription.deleted'
      subscription = event['data']['object']
      email = Stripe::Customer.retrieve(subscription['customer']).email
      user = User.find_by(email: email)
      
      if user
        user.with_lock do
          subscription = Stripe::Subscription.retrieve(subscription['id'])
          next unless subscription['status'] == 'canceled'
          next if user.stripe_subscription_id.present? && user.stripe_subscription_id != subscription['id']
          if StripeSubscriptionReplacement.other_live_subscription?(
            subscription['customer'],
            subscription['id']
          )
            Rails.logger.info("Stripe Webhook: Ignoring deletion because another live subscription exists")
            next
          end

          previous_subscription = user.current_subscription_name
          user.update!(
            stripe_subscription_id: subscription['id'],
            stripe_subscription_created_at: subscription['created'],
            current_subscription_id: nil,
            current_subscription_name: nil,
            current_subscription_expires: nil
          )
        
          # Notificar al frontend sobre la cancelación de suscripción
          notify_subscription_change(user, previous_subscription, nil)
        end
      end
    end
    head :ok
  end
  
  private

  def update_unpaid_purchase(purchase, status)
    return unless purchase

    purchase.with_lock do
      # A late failure/cancellation must not undo a confirmed payment, otherwise
      # the next success event could credit the same consumable again.
      purchase.update!(status: status) unless purchase.status == 'succeeded'
    end
  end

  def finalize_paid_subscription(invoice)
    subscription_id = invoice_subscription_id(invoice)
    return false unless subscription_id.present?
    return false unless invoice['paid'] == true || invoice['status'] == 'paid'

    subscription = Stripe::Subscription.retrieve(subscription_id)
    return false unless activate_subscription(subscription, paid_invoice_id: invoice['id'])

    StripeSubscriptionReplacement.cancel_replaced!(subscription)
    true
  end

  def activate_subscription(subscription, paid_invoice_id: nil)
    email = Stripe::Customer.retrieve(subscription['customer']).email
    user = User.find_by(email: email)
    return false unless user

    # Serialize reconciliation per user and fetch INSIDE the lock. An event
    # snapshot (or a fetch made before waiting on the lock) can already be stale.
    user.with_lock do
      subscription = Stripe::Subscription.retrieve(subscription['id'])
      return false unless %w[active trialing].include?(subscription['status'])
      return false unless current_or_newer_subscription?(user, subscription)

      if paid_invoice_id.present?
        latest_invoice = subscription['latest_invoice']
        latest_invoice = latest_invoice&.[]('id') unless latest_invoice.is_a?(String)
        return false unless latest_invoice == paid_invoice_id
      elsif StripeSubscriptionReplacement.replaced_subscription_ids(subscription).any?
        # New replacements still wait for payment; subsequent live updates to the
        # already-confirmed subscription can safely refresh its tier/expiry.
        return false unless user.stripe_subscription_id == subscription['id']
      end
      items = subscription['items']
      item_data = items && items['data']
      price_data = item_data&.first&.[]('price')
      lookup_key = price_data&.[]('lookup_key')
      config = PRODUCT_CONFIG[lookup_key]
      subscription_name = config&.[](:subscription_name)

      if subscription_name.nil? && lookup_key
        subscription_name = 'premium' if lookup_key.include?('premium')
        subscription_name = 'supreme' if lookup_key.include?('supreme')
      end

      return false unless user && subscription_name

      previous_subscription = user.current_subscription_name
      expires_at = subscription['current_period_end']
      expires_at = Time.at(expires_at) if expires_at.present? && expires_at.is_a?(Numeric)
      expires_at ||= Time.current + (config&.[](:months) || 1).months

      user.update!(
        stripe_subscription_id: subscription['id'],
        stripe_subscription_created_at: subscription['created'],
        current_subscription_name: subscription_name,
        current_subscription_expires: expires_at
      )

      notify_subscription_change(user, previous_subscription, subscription_name)
      user.update!(likes_left: 1) if user.likes_left == 0

      if paid_invoice_id.present?
        purchase = PurchasesStripe.find_by(payment_id: paid_invoice_id)
        purchase&.update!(status: "succeeded")
      end

      Rails.logger.info("Stripe Webhook: Subscription updated to #{subscription_name} (status: #{subscription['status']}, payment_confirmed: #{paid_invoice_id.present?})")
      true
    end
  end

  def current_or_newer_subscription?(user, subscription)
    return true if user.stripe_subscription_id.blank? || user.stripe_subscription_id == subscription['id']

    # Stripe timestamps have second precision. Explicit replacement metadata
    # disambiguates two plans created during the same second.
    return true if StripeSubscriptionReplacement.replaced_subscription_ids(subscription).include?(user.stripe_subscription_id)

    subscription['created'].to_i > user.stripe_subscription_created_at.to_i
  end

  def invoice_subscription_id(invoice)
    parent = invoice['parent']
    subscription_details = parent && parent['subscription_details']

    invoice['subscription'] || (subscription_details && subscription_details['subscription'])
  end
  
  # Método para notificar al frontend sobre cambios en la suscripción
  def notify_subscription_change(user, previous_subscription, new_subscription)
    return unless user
    
    if previous_subscription != new_subscription
      message = {
        type: 'subscription_change',
        user_id: user.id,
        previous_subscription: previous_subscription || "null",
        new_subscription: new_subscription || "null"
      }
      
      # Enviar mensaje a través del AliveChannel
      AliveChannel.broadcast_to(user, { type: "subscription_change", message: message })
      
      Rails.logger.info("Subscription change notification sent: #{previous_subscription || 'none'} -> #{new_subscription || 'none'}")
    end
  end
end
