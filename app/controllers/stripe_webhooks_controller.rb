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
        if config[:field] && config[:increment_value]
          user.increment!(config[:field], config[:increment_value])
        elsif config[:subscription_name] && config[:months]
          user.update!(\
            current_subscription_name: config[:subscription_name],\
            current_subscription_expires: (Time.current + config[:months].months)
          )
        end
      end
      purchase&.update(status: "succeeded")
    when 'payment_intent.canceled'
      payment_intent = event['data']['object']
      purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
      purchase&.update(status: "canceled")
    when 'payment_intent.payment_failed'
      payment_intent = event['data']['object']
      purchase = PurchasesStripe.find_by(payment_id: payment_intent['id'])
      purchase&.update(status: "failed")
    when 'customer.subscription.created', 'customer.subscription.updated'
      subscription = event['data']['object']
      email = Stripe::Customer.retrieve(subscription['customer']).email
      user = User.find_by(email: email)
      price_data = subscription['items']['data'][0]['price'] rescue nil
      lookup_key = price_data&.[]('lookup_key')
      config = PRODUCT_CONFIG[lookup_key]
      subscription_name = config&.[](:subscription_name)
      # fallback: if lookup_key starts with 'toppin_premium' or 'toppin_supreme'
      if subscription_name.nil? && lookup_key
        if lookup_key.include?('premium')
          subscription_name = 'premium'
        elsif lookup_key.include?('supreme')
          subscription_name = 'supreme'
        end
      end
      expires_at = subscription['current_period_end']
      if user && subscription_name
        if expires_at.present? && expires_at.is_a?(Numeric)
          user.update(
            current_subscription_name: subscription_name,
            current_subscription_expires: Time.at(expires_at)
          )
        else
          user.update(current_subscription_name: subscription_name)
        end
        # Update PurchasesStripe status to succeeded if payment_id matches latest_invoice
        purchase = PurchasesStripe.find_by(payment_id: subscription['latest_invoice'])
        purchase&.update(status: "succeeded")
      end
    when 'customer.subscription.deleted'
      subscription = event['data']['object']
      email = Stripe::Customer.retrieve(subscription['customer']).email
      user = User.find_by(email: email)
      user&.update(current_subscription_name: nil, current_subscription_expires: nil)
    end
    head :ok
  end
end