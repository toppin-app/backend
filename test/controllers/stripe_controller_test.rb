require "test_helper"
require "minitest/mock"
require "ostruct"

class StripeControllerTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "creating a replacement subscription records the old one without cancelling it" do
    controller = StripeController.new
    user = OpenStruct.new(email: "customer@example.com")
    customer = OpenStruct.new(id: "cus_123", email: user.email)
    price = OpenStruct.new(
      id: "price_new",
      product: "prod_new",
      unit_amount: 1_999,
      currency: "eur"
    )
    invoice = OpenStruct.new(
      id: "in_pending",
      confirmation_secret: OpenStruct.new(client_secret: "client_secret")
    )
    subscription = OpenStruct.new(id: "sub_new", latest_invoice: invoice)
    ephemeral_key = OpenStruct.new(secret: "ephemeral_secret")
    calls = []

    controller.stub(:params, { product_id: "toppin_premium_A" }) do
      controller.stub(:current_user, user) do
        controller.stub(:render, ->(**options) { options }) do
          Stripe::Price.stub(:list, ->(**) { OpenStruct.new(data: [price]) }) do
            Stripe::Customer.stub(:list, ->(**) { OpenStruct.new(data: [customer]) }) do
              Stripe::EphemeralKey.stub(:create, ->(*) { ephemeral_key }) do
                StripeSubscriptionReplacement.stub(:active_subscription_ids, ->(customer_id) { calls << [:captured, customer_id]; ["sub_old"] }) do
                  Stripe::Subscription.stub(:create, ->(**attributes) { calls << [:created, attributes]; subscription }) do
                    Stripe::Subscription.stub(:cancel, ->(*) { flunk "the old subscription was cancelled before payment" }) do
                      PurchasesStripe.stub(:create!, ->(**attributes) { calls << [:purchase, attributes] }) do
                        result = controller.create_payment_session

                        assert_equal "sub_old", calls[1][1][:metadata][StripeSubscriptionReplacement::METADATA_KEY]
                        assert_equal "default_incomplete", calls[1][1][:payment_behavior]
                        assert_equal "client_secret", result[:json][:payment_intent]
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    assert_equal :captured, calls.first.first
    assert_equal :purchase, calls.last.first
  end
end
