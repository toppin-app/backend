require "test_helper"
require "minitest/mock"

class StripeWebhooksControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  self.fixture_table_names = []

  tests StripeWebhooksController

  Purchase = Struct.new(:status) do
    def with_lock
      yield
    end

    def update!(attributes)
      self.status = attributes[:status]
    end
  end

  test "payment failure updates the purchase but never cancels the old subscription" do
    purchase = Purchase.new("pending")
    event = {
      "type" => "payment_intent.payment_failed",
      "data" => { "object" => { "id" => "pi_failed" } }
    }

    Stripe::Webhook.stub(:construct_event, event) do
      PurchasesStripe.stub(:find_by, purchase) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { flunk "failed payment cancelled the old subscription" }) do
          post :receive
        end
      end
    end

    assert_response :success
    assert_equal "failed", purchase.status
  end

  test "incomplete replacement webhook waits for payment and preserves the old subscription" do
    event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "id" => "sub_new",
          "status" => "incomplete",
          "metadata" => {
            StripeSubscriptionReplacement::METADATA_KEY => "sub_old"
          }
        }
      }
    }

    Stripe::Webhook.stub(:construct_event, event) do
      @controller.stub(:activate_subscription, false) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { flunk "incomplete subscription cancelled the old one" }) do
          post :receive
        end
      end
    end

    assert_response :success
  end

  test "paid invoice activates the new subscription before canceling the previous one" do
    controller = StripeWebhooksController.new
    invoice = { "id" => "in_paid", "paid" => true, "subscription" => "sub_new" }
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
    invoice = { "id" => "in_paid", "paid" => true, "subscription" => "sub_new" }
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

  test "previous subscription is preserved when activation raises an error" do
    controller = StripeWebhooksController.new
    invoice = { "id" => "in_paid", "paid" => true, "subscription" => "sub_new" }
    subscription = { "id" => "sub_new" }
    cancelled = false

    Stripe::Subscription.stub(:retrieve, subscription) do
      controller.stub(:activate_subscription, ->(*) { raise ActiveRecord::RecordInvalid }) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { cancelled = true }) do
          assert_raises(ActiveRecord::RecordInvalid) do
            controller.send(:finalize_paid_subscription, invoice)
          end
        end
      end
    end

    refute cancelled
  end

  test "cancellation errors occur only after activation and remain retryable" do
    controller = StripeWebhooksController.new
    invoice = { "id" => "in_paid", "paid" => true, "subscription" => "sub_new" }
    subscription = { "id" => "sub_new" }
    calls = []

    Stripe::Subscription.stub(:retrieve, subscription) do
      controller.stub(:activate_subscription, ->(*) { calls << :activated; true }) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { calls << :cancel_attempted; raise Stripe::APIConnectionError.new("temporary") }) do
          assert_raises(Stripe::APIConnectionError) do
            controller.send(:finalize_paid_subscription, invoice)
          end
        end
      end
    end

    assert_equal [:activated, :cancel_attempted], calls
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
