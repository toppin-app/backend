class StripeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:publishable_key, :create_payment_session]
  before_action :authenticate_user!

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
    "toppin_premium_C" => { subscription_name: "premium", months: 6 }
    # Agrega más productos aquí
  }

  def publishable_key
    render json: { publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'] }
  end

  # Endpoint para crear la sesión de pago (incluye comprobación/creación de customer)
  def create_payment_session
    product_key = params[:product_id]
    payment_method_id = params[:payment_method_id]

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

    config = PRODUCT_CONFIG[product_key]

    if config && config[:subscription_name] && payment_method_id.present?
      # Suscripción con Stripe Elements (modal de tarjeta)
      Stripe::PaymentMethod.attach(
        payment_method_id,
        { customer: customer.id }
      )
      Stripe::Customer.update(
        customer.id,
        invoice_settings: { default_payment_method: payment_method_id }
      )

      subscription = Stripe::Subscription.create(
        customer: customer.id,
        items: [{ price: price.id }],
        default_payment_method: payment_method_id,
        expand: ['latest_invoice.payment_intent']
      )

      PurchasesStripe.create!(
        user: user,
        payment_id: subscription.id,
        status: "pending",
        product_key: product_key,
        prize: price.unit_amount,
        increment_value: config[:increment_value],
        started_at: Time.current
      )

      render json: {
        subscription_id: subscription.id,
        client_secret: subscription.latest_invoice.payment_intent.client_secret
      }
    else
      # Pago único o suscripción sin payment_method_id (Stripe Checkout)
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

      PurchasesStripe.create!(
        user: user,
        payment_id: payment_intent.id,
        status: "pending",
        product_key: product_key,
        prize: price.unit_amount,
        increment_value: config ? config[:increment_value] : nil,
        started_at: Time.current
      )

      render json: {
        customer: customer.id,
        payment_intent: payment_intent.client_secret,
        payment_id: payment_intent.id,
        ephemeral_key: ephemeral_key.secret,
        product_id: price.product,
        price_id: price.id
      }
    end
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :bad_request
  end
end