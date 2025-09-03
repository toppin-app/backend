class PurchasesStripeController < ApplicationController
  before_action :authenticate_user!

  def status
    purchase = current_user.purchases_stripes.find_by(payment_id: params[:payment_id])
    if purchase
      render json: { status: purchase.status, product_key: purchase.product_key, prize: purchase.prize, increment: purchase.increment }
    else
      render json: { error: "Purchase not found" }, status: :not_found
    end
  end
end