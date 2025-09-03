class StripeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:publishable_key, :create_payment_session]
  before_action :authenticate_user!

  PRODUCT_MAP = {
    "toppin_sweet_A" => "price_1S2umXQmb7ZC5DaSZQ190E2f",
    "toppin_sweet_B" => "price_1S2umkQmb7ZC5DaSE3DbFnZH",
    "toppin_sweet_C" => "price_1S2umwQmb7ZC5DaSPXsWkr2T"
  }

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
    price_id = PRODUCT_MAP[product_key]
    increment_value = INCREMENT_MAP[product_key]

    return render json: { error: 'Product ID missing' }, status: :bad_request unless price_id

    user = current_user
    email = user.email

    # Comprobar/crear el customer en Stripe
    customers = Stripe::Customer.list(email: email).data
    customer = customers.find { |c| c.email == email }
    customer ||= Stripe::Customer.create(email: email)

    price = Stripe::Price.retrieve(price_id)

    ephemeral_key = Stripe::EphemeralKey.create(
      { customer: customer.id },
      { stripe_version: ENV['STRIPE_API_VERSION'] }
    )

    payment_intent = Stripe::PaymentIntent.create(
      amount: price.unit_amount,
      currency: price.currency,
      customer: customer.id,
      payment_method: 'pm_card_visa',
      metadata: { product_id: price.product, product_key: product_key }
    )

    # Incrementa el campo según la clave
    user.increment!(:spin_roulette_available, increment_value)

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