class StripeController < ApplicationController
  before_action :authenticate_user!

  # Endpoint para crear la sesión de pago (incluye comprobación/creación de customer)
  def create_payment_session
    product_id = params[:product_id]
    return render json: { error: 'Product ID missing' }, status: :bad_request unless product_id

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


    # Crear y confirmar el PaymentIntent con método de prueba
    payment_intent = Stripe::PaymentIntent.create(
      amount: price.unit_amount,
      currency: price.currency,
      customer: customer.id,
      payment_method: 'pm_card_visa', # método de pago de prueba
      confirm: true,
      metadata: { product_id: product_id }
    )

    if product_id == 'prod_SxKyBS6mNLoICU'
      user.increment!(:boost_available)
    end
    
    # Crear Ephemeral Key
    ephemeral_key = Stripe::EphemeralKey.create(
      { customer: customer.id },
      { stripe_version: ENV['STRIPE_API_VERSION'] }
    )

    render json: {
      customer: customer,
      payment_intent: payment_intent,
      ephemeral_key: ephemeral_key.secret,
      product_id: product_id,
      price_id: price.id
    }
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :bad_request
  end
end