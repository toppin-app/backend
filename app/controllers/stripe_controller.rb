class StripeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:publishable_key, :create_payment_session]
  before_action :authenticate_user!

    PRODUCT_MAP = {
    "toppin_sweet_A" => "prod_SysXKSqnpFYDYS"
    # Agrega más mapeos aquí
  }

  def publishable_key
    render json: { publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'] }
  end

  # Endpoint para crear la sesión de pago (incluye comprobación/creación de customer)
  def create_payment_session
    product_key = params[:product_id]
    product_id = PRODUCT_MAP[product_key]

    return render json: { error: 'Product ID missing' }, status: :bad_request unless product_key

    user = current_user
    email = user.email

    # Comprobar/crear el customer en Stripe
    customers = Stripe::Customer.list(email: email).data
    customer = customers.find { |c| c.email == email }
    unless customer
      customer = Stripe::Customer.create(email: email)
    end

    # Obtener el precio del producto desde Stripe
    prices = Stripe::Price.list(product: product_id, limit: 1).data
    return render json: { error: 'Price not found for product' }, status: :not_found if prices.empty?
    price = prices.first


    quantity = params[:quantity].to_i > 0 ? params[:quantity].to_i : 1
    
    # Crear Ephemeral Key
    ephemeral_key = Stripe::EphemeralKey.create(
      { customer: customer.id },
      { stripe_version: ENV['STRIPE_API_VERSION'] }
    )
    
    # Crear y confirmar el PaymentIntent con método de prueba
    payment_intent = Stripe::PaymentIntent.create(
      amount: price.unit_amount,
      currency: price.currency,
      customer: customer.id,
      payment_method: 'pm_card_visa',
      metadata: { product_id: product_id}
    )


    if product_id == 'prod_SysXKSqnpFYDYS'
      user.increment!(:spin_roulette_available)
    end

    render json: {
      customer: customer.id,
      payment_intent: payment_intent.client_secret,
      ephemeral_key: ephemeral_key.secret,
      product_id: product_id,
      price_id: price.id
    }
    
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :bad_request
  end
end