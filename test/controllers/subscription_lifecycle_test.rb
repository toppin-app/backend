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
      'metadata' => {}, 'current_period_end' => 1.month.from_now.to_i,
      'items' => { 'data' => [{ 'price' => { 'lookup_key' => "toppin_#{level}_A" } }] } }.merge(attrs.transform_keys(&:to_s))
  end

  def deliver(type, object)
    event = { 'type' => type, 'data' => { 'object' => object } }
    Stripe::Webhook.stub(:construct_event, event) do
      Stripe::Customer.stub(:retrieve, OpenStruct.new(email: @user.email)) do
        AliveChannel.stub(:broadcast_to, ->(user, payload) { @broadcasts << payload }) { post :receive }
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
    StripeSubscriptionReplacement.stub(:other_live_subscription?, false) { deliver('customer.subscription.deleted', subscription) }
    assert_nil @user.reload.current_subscription_name
    assert_nil @user.current_subscription_expires
    assert_equal 'null', @broadcasts.first[:message][:new_subscription]
  end

  test 'old deletion does not revoke another live subscription' do
    StripeSubscriptionReplacement.stub(:other_live_subscription?, true) { deliver('customer.subscription.deleted', subscription) }
    assert_equal 'premium', @user.reload.current_subscription_name
  end

  test 'duplicate level update does not duplicate change notifications' do
    2.times { deliver('customer.subscription.updated', subscription) }
    assert_equal 1, @broadcasts.size
  end

  test 'KNOWN BUG stale event can downgrade the newer level' do
    deliver('customer.subscription.updated', subscription('supreme'))
    deliver('customer.subscription.updated', subscription('premium'))
    assert_equal 'premium', @user.reload.current_subscription_name
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

  test 'KNOWN BUG replaying a consumable payment credits the balance twice' do
    @user.update!(boost_available: 0)
    payment = Stripe::StripeObject.construct_from({ id: 'pi_test', customer: 'cus_test', metadata: { product_key: 'power_sweet_A' } })
    PurchasesStripe.stub(:find_by, nil) do
      2.times { deliver('payment_intent.succeeded', payment) }
    end
    assert_equal 2, @user.reload.boost_available
  end

  test 'paid replacement persists access before attempting cancellation' do
    sub = subscription(metadata: { 'replaces_subscription_ids' => 'sub_old' })
    observed = []
    Stripe::Subscription.stub(:retrieve, sub) do
      PurchasesStripe.stub(:find_by, nil) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, ->(*) { observed << @user.reload.current_subscription_name }) do
          deliver('invoice.paid', { 'id' => 'in_test', 'subscription' => sub['id'] })
        end
      end
    end
    assert_equal ['supreme'], observed
  end

  test 'KNOWN BUG a paid historical invoice can activate a canceled subscription' do
    sub = subscription(status: 'canceled')
    Stripe::Subscription.stub(:retrieve, sub) do
      PurchasesStripe.stub(:find_by, nil) do
        StripeSubscriptionReplacement.stub(:cancel_replaced!, nil) do
          deliver('invoice.paid', { 'id' => 'in_old', 'subscription' => sub['id'] })
        end
      end
    end
    assert_equal 'supreme', @user.reload.current_subscription_name
  end
end
