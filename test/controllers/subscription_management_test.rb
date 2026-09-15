require 'test_helper'
require 'minitest/mock'
require 'ostruct'

class SubscriptionManagementTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  def with_gateway(subscriptions: [], customer: true)
    controller = StripeController.new
    user = OpenStruct.new(email: 'test@example.com')
    customers = customer ? [OpenStruct.new(id: 'cus_test', email: user.email)] : []
    controller.stub(:current_user, user) do
      controller.stub(:render, ->(**options) { options }) do
        Stripe::Customer.stub(:list, ->(**) { OpenStruct.new(data: customers) }) do
          Stripe::Subscription.stub(:list, ->(**) { OpenStruct.new(data: subscriptions) }) { yield controller }
        end
      end
    end
  end

  test 'no Stripe customer returns inactive without error' do
    with_gateway(customer: false) do |controller|
      assert_equal false, controller.subscription_status[:json][:active]
      assert_equal :not_found, controller.cancel_subscription[:status]
    end
  end

  test 'cancel schedules end of period without immediate cancellation or local revocation' do
    calls = []
    with_gateway(subscriptions: [OpenStruct.new(id: 'sub_current')]) do |controller|
      Stripe::Subscription.stub(:update, ->(*args) { calls << args }) do
        Stripe::Subscription.stub(:cancel, ->(*) { flunk 'must retain paid access' }) do
          assert controller.cancel_subscription[:json][:success]
        end
      end
    end
    assert_equal [['sub_current', { cancel_at_period_end: true }]], calls
  end

  test 'no subscription to cancel returns not found' do
    with_gateway { |controller| assert_equal :not_found, controller.cancel_subscription[:status] }
  end

  test 'KNOWN BUG newest incomplete subscription masks the older active plan' do
    item = OpenStruct.new(price: OpenStruct.new(nickname: 'Supreme', unit_amount: 2000, currency: 'eur'), current_period_end: 1.month.from_now.to_i)
    sub = OpenStruct.new(status: 'incomplete', items: OpenStruct.new(data: [item]), cancel_at_period_end: false)
    with_gateway(subscriptions: [sub]) do |controller|
      assert_equal false, controller.subscription_status[:json][:active]
    end
  end
end
