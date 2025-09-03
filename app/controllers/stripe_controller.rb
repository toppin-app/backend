class StripeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:publishable_key, :create_payment_session]
  before_action :authenticate_user!

  INCREMENT_MAP = {
    "toppin_sweet_A" => 5,
    "toppin_sweet_B" => 10,
    "toppin_sweet_C" => 20
  }

  def publishable_key
    render json: { publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'] }
  end

  # Endpoint para crear la sesión de pago (incluye comprobación/creación de customer)
  def create_payment_session
    product_key = params[:product_id]

    price_list = Stripe::Price.list(
      lookup_keys: [product_key],
      limit: 1
    )
    price = price_list.data.first

    return render json: { error: 'Price not found' }, status: :not_found unless price

    user = current_user
    email = user.email

    customers = Stripe::Customer.list(email: email).data
    customer = customers.find { |c| c.email == email }
    customer ||= Stripe::Customer.create(email: email)

    ephemeral_key = Stripe::EphemeralKey.create(
      { customer: customer.id },
      { stripe_version: ENV['STRIPE_API_VERSION'] }
    )

    payment_intent = Stripe::PaymentIntent.create(
      amount: price.unit_amount,
      currency: price.currency,
      customer: customer.id,
      metadata: { product_id: price.product, product_key: product_key }
    )

    render json: {
      customer: customer.id,
      payment_intent: payment_intent.client_secret,
      ephemeral_key: ephemeral_key.secret,
      product_id: price.product,
      price_id: price.id
    }
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :bad_request
  end
end