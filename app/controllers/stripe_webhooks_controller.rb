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
        purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
        if user && config
          user.increment!(config[:field], config[:increment_value]) if config[:field] && config[:increment_value]
        end
        purchase&.update(status: "succeeded")
      end
    when 'payment_intent.canceled'
      payment_intent = event['data']['object']
      purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
      purchase&.update(status: "canceled")
    when 'payment_intent.payment_failed'
      payment_intent = event['data']['object']
      purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
      purchase&.update(status: "failed")
    when 'invoice.paid'
      finalize_paid_subscription(event['data']['object'])
    when 'customer.subscription.created', 'customer.subscription.updated'
      subscription = event['data']['object']
      
      # Una suscripción incompleta no debe sustituir a la vigente.
      unless ['active', 'trialing'].include?(subscription['status'])
        Rails.logger.info("Stripe Webhook: Skipping subscription #{subscription['id']} with status #{subscription['status']}")
        head :ok and return
      end

      if StripeSubscriptionReplacement.replaced_subscription_ids(subscription).any?
        Rails.logger.info("Stripe Webhook: Waiting for paid invoice before replacing subscriptions with #{subscription['id']}")
      else
        activate_subscription(subscription)
      end
    when 'customer.subscription.deleted'
      subscription = event['data']['object']
      email = Stripe::Customer.retrieve(subscription['customer']).email
      user = User.find_by(email: email)
      
      if user
        if StripeSubscriptionReplacement.other_live_subscription?(
          subscription['customer'],
          subscription['id']
        )
          Rails.logger.info("Stripe Webhook: Ignoring deletion of replaced subscription #{subscription['id']} for user #{user.id}")
          head :ok and return
        end

        previous_subscription = user.current_subscription_name
        user.update!(
          current_subscription_id: nil,
          current_subscription_name: nil,
          current_subscription_expires: nil
        )
        
        # Notificar al frontend sobre la cancelación de suscripción
        notify_subscription_change(user, previous_subscription, nil)
      end
    end
    head :ok
  end
  
  private

  def finalize_paid_subscription(invoice)
    subscription_id = invoice_subscription_id(invoice)
    return false unless subscription_id.present?

    subscription = Stripe::Subscription.retrieve(subscription_id)
    return false unless activate_subscription(subscription, paid_invoice_id: invoice['id'])

    StripeSubscriptionReplacement.cancel_replaced!(subscription)
    true
  end

  def activate_subscription(subscription, paid_invoice_id: nil)
    email = Stripe::Customer.retrieve(subscription['customer']).email
    user = User.find_by(email: email)
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
      current_subscription_name: subscription_name,
      current_subscription_expires: expires_at
    )

    notify_subscription_change(user, previous_subscription, subscription_name)
    user.update!(likes_left: 1) if user.likes_left == 0

    if paid_invoice_id.present?
      purchase = PurchasesStripe.find_by(payment_id: paid_invoice_id)
      purchase&.update!(status: "succeeded")
    end

    Rails.logger.info("Stripe Webhook: User #{user.id} subscription updated to #{subscription_name} (status: #{subscription['status']}, payment_confirmed: #{paid_invoice_id.present?})")
    true
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
      
      Rails.logger.info("Subscription change notification sent to user #{user.id}: #{previous_subscription || 'none'} -> #{new_subscription || 'none'}")
    end
  end
end
