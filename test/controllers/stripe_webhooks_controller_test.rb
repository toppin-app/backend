require "test_helper"

class StripeWebhooksControllerTest < ActiveSupport::TestCase
  test "paid invoice activates the new subscription before canceling the previous one" do
    controller = StripeWebhooksController.new
    invoice = { "id" => "in_paid", "subscription" => "sub_new" }
    subscription = { "id" => "sub_new" }
    calls = []

    Stripe::Subscription.stub(:retrieve, subscription) do
      controller.stub(:activate_subscription, ->(*) { calls << :activated; true }) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { calls << :cancelled }) do
          result = controller.send(:finalize_paid_subscription, invoice)

          assert result
        end
      end
    end

    assert_equal [:activated, :cancelled], calls
  end

  test "previous subscription is preserved when activation cannot be completed" do
    controller = StripeWebhooksController.new
    invoice = { "id" => "in_paid", "subscription" => "sub_new" }
    subscription = { "id" => "sub_new" }
    cancelled = false

    Stripe::Subscription.stub(:retrieve, subscription) do
      controller.stub(:activate_subscription, false) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { cancelled = true }) do
          result = controller.send(:finalize_paid_subscription, invoice)

          refute result
        end
      end
    end

    refute cancelled
  end

  test "invoice without a subscription does not cancel anything" do
    controller = StripeWebhooksController.new
    cancelled = false

    StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { cancelled = true }) do
      result = controller.send(:finalize_paid_subscription, { "id" => "in_one_off" })

      refute result
    end

    refute cancelled
  end

  test "supports the current Stripe invoice parent shape" do
    controller = StripeWebhooksController.new
    invoice = {
      "parent" => {
        "subscription_details" => { "subscription" => "sub_new" }
      }
    }

    assert_equal "sub_new", controller.send(:invoice_subscription_id, invoice)
  end
end
