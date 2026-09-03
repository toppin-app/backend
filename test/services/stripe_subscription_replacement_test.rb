require "minitest/autorun"
require_relative "../../app/services/stripe_subscription_replacement"

class StripeSubscriptionReplacementTest < Minitest::Test
  Subscription = Struct.new(:id, :status, :metadata, keyword_init: true)
  ListResult = Struct.new(:data)

  class FakeSubscriptions
    attr_reader :cancelled_ids, :list_calls, :retrieved_ids

    def initialize(listed: [], stored: {})
      @listed = listed
      @stored = stored
      @cancelled_ids = []
      @list_calls = []
      @retrieved_ids = []
    end

    def list(params)
      @list_calls << params
      ListResult.new(@listed)
    end

    def retrieve(subscription_id)
      @retrieved_ids << subscription_id
      @stored.fetch(subscription_id)
    end

    def cancel(subscription_id)
      @cancelled_ids << subscription_id
    end
  end

  def test_capturing_previous_subscriptions_does_not_cancel_them
    gateway = FakeSubscriptions.new(
      listed: [
        Subscription.new(id: "sub_old", status: "active"),
        Subscription.new(id: "sub_old", status: "active")
      ]
    )

    ids = StripeSubscriptionReplacement.active_subscription_ids(
      "cus_123",
      subscriptions: gateway
    )

    assert_equal ["sub_old"], ids
    assert_equal [], gateway.cancelled_ids
    assert_equal [
      { customer: "cus_123", status: "active", limit: 100 }
    ], gateway.list_calls
  end

  def test_metadata_records_only_unique_previous_subscription_ids
    metadata = StripeSubscriptionReplacement.metadata_for(
      ["sub_first", nil, "sub_first", "sub_second"]
    )

    assert_equal(
      { "replaces_subscription_ids" => "sub_first,sub_second" },
      metadata
    )
  end

  def test_cancels_only_recorded_non_terminal_subscriptions
    gateway = FakeSubscriptions.new(
      stored: {
        "sub_active" => Subscription.new(id: "sub_active", status: "active"),
        "sub_past_due" => Subscription.new(id: "sub_past_due", status: "past_due"),
        "sub_cancelled" => Subscription.new(id: "sub_cancelled", status: "canceled")
      }
    )
    replacement = Subscription.new(
      id: "sub_new",
      status: "active",
      metadata: {
        "replaces_subscription_ids" =>
          "sub_active,sub_new,sub_cancelled,sub_past_due,sub_active"
      }
    )

    StripeSubscriptionReplacement.cancel_replaced!(
      replacement,
      subscriptions: gateway
    )

    assert_equal ["sub_active", "sub_past_due"], gateway.cancelled_ids
    refute_includes gateway.retrieved_ids, "sub_new"
  end

  def test_does_nothing_without_replacement_metadata
    gateway = FakeSubscriptions.new
    subscription = Subscription.new(
      id: "sub_new",
      status: "active",
      metadata: {}
    )

    StripeSubscriptionReplacement.cancel_replaced!(
      subscription,
      subscriptions: gateway
    )

    assert_equal [], gateway.retrieved_ids
    assert_equal [], gateway.cancelled_ids
  end

  def test_detects_another_live_subscription_when_an_old_one_is_deleted
    gateway = FakeSubscriptions.new(
      listed: [
        Subscription.new(id: "sub_deleted", status: "canceled"),
        Subscription.new(id: "sub_new", status: "active")
      ]
    )

    result = StripeSubscriptionReplacement.other_live_subscription?(
      "cus_123",
      "sub_deleted",
      subscriptions: gateway
    )

    assert result
    assert_equal [
      { customer: "cus_123", status: "all", limit: 100 }
    ], gateway.list_calls
  end

  def test_does_not_treat_the_deleted_or_incomplete_subscription_as_a_replacement
    gateway = FakeSubscriptions.new(
      listed: [
        Subscription.new(id: "sub_deleted", status: "active"),
        Subscription.new(id: "sub_incomplete", status: "incomplete")
      ]
    )

    result = StripeSubscriptionReplacement.other_live_subscription?(
      "cus_123",
      "sub_deleted",
      subscriptions: gateway
    )

    refute result
  end
end
