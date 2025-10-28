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
    "toppin_premium_C" => { subscription_name: "premium", months: 6 },
    "toppin_premium_AA" => { subscription_name: "premium", months: 12 }
    # Agrega más productos aquí
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

    
    # 👇 Cancelar suscripciones activas antes de crear una nueva
    active_subs = Stripe::Subscription.list(customer: customer.id, status: 'active').data
    active_subs.each do |sub|
      Stripe::Subscription.cancel(sub.id) # Cancela inmediatamente
      # Si prefieres cancelar al final del periodo, usa:
      # Stripe::Subscription.update(sub.id, cancel_at_period_end: true)
    end

  
    ephemeral_key = Stripe::EphemeralKey.create(
      { customer: customer.id },
      { stripe_version: ENV['STRIPE_API_VERSION'] }
    )

    config = PRODUCT_CONFIG[product_key]
    if product_key.start_with?('toppin_supreme_', 'toppin_premium_')
    subscription = Stripe::Subscription.create(
      customer: customer.id,
      items: [{ price: price.id }],
      payment_behavior: 'default_incomplete',
      payment_settings: {
        save_default_payment_method: 'on_subscription'
      },
      expand: ['latest_invoice.confirmation_secret'],
      metadata: { product_id: price.product, product_key: product_key }
    )
    
    # Asegurar que el customer tenga el email actualizado
    Stripe::Customer.update(customer.id, email: email) if customer.email != email

    PurchasesStripe.create!(
      user: user,
      payment_id: subscription.latest_invoice.id,
      status: "pending",
      product_key: product_key,
      prize: price.unit_amount,
      increment_value: config ? config[:increment_value] : nil,
      started_at: Time.current
    )

    Rails.logger.info {subscription.latest_invoice}

    render json: {
      customer: customer.id,
      payment_id: subscription.latest_invoice.id,
      payment_intent: subscription.latest_invoice.confirmation_secret.client_secret,
      product_id: price.product,
      price_id: price.id,
      ephemeral_key: ephemeral_key.secret,
      product_key: product_key
    }
  else
      # Pago único

      payment_intent = Stripe::PaymentIntent.create(
        amount: price.unit_amount,
        currency: price.currency,
        customer: customer.id,
        receipt_email: email,
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
        price_id: price.id,
        product_key: product_key
      }
    end

  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :bad_request
  end

  def subscription_status
    user = current_user
    email = user.email

    customers = Stripe::Customer.list(email: email).data
    customer = customers.find { |c| c.email == email }
    
    # Si no tiene customer en Stripe, simplemente no tiene suscripción activa
    unless customer
      return render json: { 
        active: false, 
        subscription_name: nil,
        will_renew: false,
        payment_method: nil,
        last4: nil,
        current_period_end: nil,
        subscribed_at: nil,
        price: nil,
        currency: nil,
        status: nil
      }
    end

    subscriptions = Stripe::Subscription.list(customer: customer.id, limit: 1).data
    subscription = subscriptions.first

    
    if subscription
      payment_method_id = subscription.default_payment_method
      payment_method = payment_method_id ? Stripe::PaymentMethod.retrieve(payment_method_id) : nil

      item = subscription.items.data.first
      price = item&.price
      subscription_name = price&.nickname

      if subscription_name.blank? && price&.product
        product = Stripe::Product.retrieve(price.product)
        subscription_name = product.name
      end

      current_period_end = item ? Time.at(item.current_period_end) : nil
      subscribed_at = subscription.created ? Time.at(subscription.created) : nil

      render json: {
        active: subscription.status == "active",
        will_renew: !subscription.cancel_at_period_end,
        subscription_name: subscription_name,
        payment_method: payment_method ? payment_method.card.brand : nil,
        last4: payment_method ? payment_method.card.last4 : nil,
        current_period_end: current_period_end,
        subscribed_at: subscribed_at,
        price: price ? price.unit_amount : nil,
        currency: price ? price.currency : nil,
        status: subscription.status
      }
    else
      render json: { active: false, subscription_name: nil }
    end
  end

  def cancel_subscription
    user = current_user
    email = user.email

    customers = Stripe::Customer.list(email: email).data
    customer = customers.find { |c| c.email == email }
    return render json: { error: "Customer not found" }, status: :not_found unless customer

    subscriptions = Stripe::Subscription.list(customer: customer.id, status: 'active').data
    subscription = subscriptions.first
    return render json: { error: "No active subscription found" }, status: :not_found unless subscription

    # Marcar para cancelar al final del periodo actual
    Stripe::Subscription.update(subscription.id, cancel_at_period_end: true)

    render json: { success: true, message: "La suscripción no se renovará al final del periodo actual." }
  end
end