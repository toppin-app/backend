require 'test_helper'
require 'minitest/mock'
require 'ostruct'

class SubscriptionLifecycleTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  self.fixture_table_names = []
  tests StripeWebhooksController
  setup do
    @user = User.create!(email: 'lifecycle@example.com', password: 'Secure123!', current_subscription_name: 'premium')
    @broadcasts = []
  end

  def subscription(level = 'supreme', **attrs)
    { 'id' => "sub_#{level}", 'status' => 'active', 'customer' => 'cus_test',
      'metadata' => {}, 'created' => 100, 'latest_invoice' => 'in_test', 'current_period_end' => 1.month.from_now.to_i,
      'items' => { 'data' => [{ 'price' => { 'lookup_key' => "toppin_#{level}_A" } }] } }.merge(attrs.transform_keys(&:to_s))
  end

  def deliver(type, object, live: nil)
    event = { 'type' => type, 'data' => { 'object' => object } }
    Stripe::Webhook.stub(:construct_event, event) do
      Stripe::Customer.stub(:retrieve, OpenStruct.new(email: @user.email)) do
        run = ->(*) { AliveChannel.stub(:broadcast_to, ->(user, payload) { @broadcasts << payload }) { post :receive } }
        if type.start_with?('customer.subscription.')
          Stripe::Subscription.stub(:retrieve, live || object, &run)
        else
          run.call
        end
      end
    end
  end

  test 'active subscription updates level expiry and notifies' do
    sub = subscription
    deliver('customer.subscription.updated', sub)
    assert_response :success
    assert_equal 'supreme', @user.reload.current_subscription_name
    assert_equal sub['current_period_end'], @user.current_subscription_expires.to_i
    assert_equal 'supreme', @broadcasts.first[:message][:new_subscription]
  end

  test 'replacement update before payment preserves previous level' do
    deliver('customer.subscription.updated', subscription(metadata: { 'replaces_subscription_ids' => 'sub_old' }))
    assert_equal 'premium', @user.reload.current_subscription_name
    assert_empty @broadcasts
  end

  %w[incomplete incomplete_expired past_due unpaid paused canceled].each do |status|
    test "#{status} update does not activate a higher level" do
      deliver('customer.subscription.updated', subscription(status: status))
      assert_equal 'premium', @user.reload.current_subscription_name
    end
  end

  test 'deletion removes access when no other live subscription exists' do
    StripeSubscriptionReplacement.stub(:other_live_subscription?, false) { deliver('customer.subscription.deleted', subscription(status: 'canceled')) }
    assert_nil @user.reload.current_subscription_name
    assert_nil @user.current_subscription_expires
    assert_equal 'null', @broadcasts.first[:message][:new_subscription]
  end

  test 'old deletion does not revoke another live subscription' do
    StripeSubscriptionReplacement.stub(:other_live_subscription?, true) { deliver('customer.subscription.deleted', subscription(status: 'canceled')) }
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'duplicate level update does not duplicate change notifications' do
    2.times { deliver('customer.subscription.updated', subscription) }
    assert_equal 1, @broadcasts.size
  end

  test 'stale event from a different subscription cannot downgrade the newer level' do
    deliver('customer.subscription.updated', subscription('supreme', created: 200))
    deliver('customer.subscription.updated', subscription('premium', created: 100))
    assert_equal 'supreme', @user.reload.current_subscription_name
  end

  test 'late snapshot of the same subscription uses its current tier' do
    live = subscription('supreme', id: 'sub_same')
    deliver('customer.subscription.updated', subscription('premium', id: 'sub_same'), live: live)
    assert_equal 'supreme', @user.reload.current_subscription_name
  end

  test 'late active snapshot cannot reactivate a now canceled subscription' do
    @user.update!(current_subscription_name: nil)
    deliver('customer.subscription.updated', subscription, live: subscription(status: 'canceled'))
    assert_nil @user.reload.current_subscription_name
  end

  test 'deletion retains identity so a still active older plan cannot restore access' do
    @user.update!(stripe_subscription_id: 'sub_supreme', stripe_subscription_created_at: 200)
    StripeSubscriptionReplacement.stub(:other_live_subscription?, false) do
      deliver('customer.subscription.deleted', subscription(status: 'canceled', created: 200))
    end
    deliver('customer.subscription.updated', subscription('premium', created: 100))
    assert_nil @user.reload.current_subscription_name
    assert_equal 'sub_supreme', @user.stripe_subscription_id
  end

  test 'old deletion cannot clear the tracked subscription even if the remote list is stale' do
    @user.update!(stripe_subscription_id: 'sub_new', stripe_subscription_created_at: 200)
    StripeSubscriptionReplacement.stub(:other_live_subscription?, false) do
      deliver('customer.subscription.deleted', subscription(status: 'canceled'))
    end
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'historical invoice of a live subscription cannot overwrite the current plan' do
    Stripe::Subscription.stub(:retrieve, subscription(latest_invoice: 'in_new')) do
      StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { flunk 'historical invoice canceled a plan' }) do
        deliver('invoice.paid', { 'id' => 'in_old', 'paid' => true, 'subscription' => 'sub_supreme' })
      end
    end
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'a paid old plan cannot replace a newer tracked subscription' do
    @user.update!(current_subscription_name: 'supreme', stripe_subscription_id: 'sub_new', stripe_subscription_created_at: 200)
    Stripe::Subscription.stub(:retrieve, subscription('premium', created: 100)) do
      StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { flunk 'old plan canceled subscriptions' }) do
        deliver('invoice.paid', { 'id' => 'in_test', 'paid' => true, 'subscription' => 'sub_premium' })
      end
    end
    assert_equal 'supreme', @user.reload.current_subscription_name
  end

  test 'unpaid invoice never activates or cancels' do
    Stripe::Subscription.stub(:retrieve, ->(*) { flunk 'unpaid invoice was processed' }) do
      deliver('invoice.paid', { 'id' => 'in_test', 'paid' => false, 'subscription' => 'sub_supreme' })
    end
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'same-second replacement can activate after payment and retry failed cleanup' do
    @user.update!(stripe_subscription_id: 'sub_old', stripe_subscription_created_at: 100)
    sub = subscription(metadata: { 'replaces_subscription_ids' => 'sub_old' })
    invoice = { 'id' => 'in_test', 'paid' => true, 'subscription' => sub['id'] }
    attempts = 0
    Stripe::Subscription.stub(:retrieve, sub) do
      StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) {
        attempts += 1
        assert_equal 'supreme', @user.reload.current_subscription_name
        raise Stripe::APIConnectionError.new('temporary') if attempts == 1
      }) do
        assert_raises(Stripe::APIConnectionError) { deliver('invoice.paid', invoice) }
        deliver('invoice.paid', invoice)
      end
    end
    assert_equal 2, attempts
    assert_equal 1, @broadcasts.size
    assert_equal 'sub_supreme', @user.reload.stripe_subscription_id
  end

  test 'live updates of a confirmed replacement are not blocked by replacement metadata' do
    @user.update!(stripe_subscription_id: 'sub_supreme', stripe_subscription_created_at: 100)
    sub = subscription(metadata: { 'replaces_subscription_ids' => 'sub_old' })
    deliver('customer.subscription.updated', sub)
    assert_equal 'supreme', @user.reload.current_subscription_name
  end

  test 'late failure cannot reset succeeded status and allow a second credit' do
    @user.update!(boost_available: 0)
    PurchasesStripe.create!(user: @user, payment_id: 'pi_test', product_key: 'power_sweet_A')
    payment = Stripe::StripeObject.construct_from({ id: 'pi_test', customer: 'cus_test', metadata: { product_key: 'power_sweet_A' } })
    deliver('payment_intent.succeeded', payment)
    deliver('payment_intent.payment_failed', payment)
    deliver('payment_intent.canceled', payment)
    deliver('payment_intent.succeeded', payment)
    assert_equal 1, @user.reload.boost_available
    assert_equal 'succeeded', PurchasesStripe.find_by!(payment_id: 'pi_test').status
  end

  test 'KNOWN BUG unrecognized product containing premium is accepted' do
    @user.update!(current_subscription_name: nil)
    deliver('customer.subscription.updated', subscription('not_a_real_premium_product'))
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'KNOWN BUG activation leaves old product identifier untouched' do
    @user.update!(current_subscription_id: 'toppin_premium_mensual')
    deliver('customer.subscription.updated', subscription)
    assert_equal 'supreme', @user.reload.current_subscription_name
    assert_equal 'toppin_premium_mensual', @user.current_subscription_id
  end

  test 'invalid webhook signature cannot mutate subscription' do
    Stripe::Webhook.stub(:construct_event, ->(*) { raise Stripe::SignatureVerificationError.new('invalid', 'test-signature') }) { post :receive }
    assert_response :bad_request
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'replaying a consumable payment credits the balance only once' do
    @user.update!(boost_available: 0)
    payment = Stripe::StripeObject.construct_from({ id: 'pi_test', customer: 'cus_test', metadata: { product_key: 'power_sweet_A' } })
    purchase = PurchasesStripe.create!(user: @user, payment_id: 'pi_test', product_key: 'power_sweet_A')
    2.times { deliver('payment_intent.succeeded', payment) }
    assert_equal 1, @user.reload.boost_available
    assert_equal 'succeeded', purchase.reload.status
  end

  test 'paid replacement persists access before attempting cancellation' do
    sub = subscription(metadata: { 'replaces_subscription_ids' => 'sub_old' })
    observed = []
    Stripe::Subscription.stub(:retrieve, sub) do
      PurchasesStripe.stub(:find_by, nil) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { observed << @user.reload.current_subscription_name }) do
          deliver('invoice.paid', { 'id' => 'in_test', 'paid' => true, 'subscription' => sub['id'] })
        end
      end
    end
    assert_equal ['supreme'], observed
  end

  test 'a paid historical invoice cannot activate a canceled subscription' do
    sub = subscription(status: 'canceled')
    Stripe::Subscription.stub(:retrieve, sub) do
      PurchasesStripe.stub(:find_by, nil) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, nil) do
          deliver('invoice.paid', { 'id' => 'in_old', 'paid' => true, 'subscription' => sub['id'] })
        end
      end
    end
    assert_equal 'premium', @user.reload.current_subscription_name
  end
end
