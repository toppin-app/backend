class StripeWebhooksController < ApplicationController
  # Stripe recomienda desactivar CSRF para webhooks
  skip_before_action :verify_authenticity_token

  PRODUCT_CONFIG = {
    "toppin_sweet_A" => { field: :spin_roulette_available, increment: 5 },
    "toppin_sweet_B" => { field: :spin_roulette_available, increment: 10 },
    "toppin_sweet_C" => { field: :spin_roulette_available, increment: 20 },
    "power_sweet_A"    => { field: :boost_available, increment: 1 },
    "power_sweet_B"    => { field: :boost_available, increment: 5 },
    "power_sweet_C"    => { field: :boost_available, increment: 10 },
    "super_sweet_A"    => { field: :superlike_available, increment: 5 },
    "super_sweet_B"    => { field: :superlike_available, increment: 25 },
    "super_sweet_C"    => { field: :superlike_available, increment: 60 }
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

    payment_intent = event['data']['object']
    product_key = payment_intent['metadata']['product_key']
    email = Stripe::Customer.retrieve(payment_intent['customer']).email
    user = User.find_by(email: email)
    purchase = Purchases.find_by(payment_id: payment_intent['id'])

    case event['type']
    when 'payment_intent.succeeded'
      config = PRODUCT_CONFIG[product_key]
      if user && config
        user.increment!(config[:field], config[:increment])
      end
      purchase&.update(status: "succeeded")
    when 'payment_intent.canceled'
      purchase&.update(status: "canceled")
    when 'payment_intent.payment_failed'
      purchase&.update(status: "failed")
    end

    head :ok
  end
end