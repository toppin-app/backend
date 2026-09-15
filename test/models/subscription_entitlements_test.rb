require 'test_helper'

class SubscriptionEntitlementsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  [nil, '', 'premium', 'supreme', 'free', 'null', 'unknown'].each do |level|
    test "characterize entitlement predicates for #{level.inspect}" do
      user = User.new(current_subscription_name: level)
      assert_equal level.present?, user.is_premium
      assert_equal %w[premium supreme].include?(level), !!user.premium_or_supreme?
    end
  end

  test 'KNOWN BUG expired levels still grant access' do
    %w[premium supreme].each do |level|
      user = User.new(current_subscription_name: level, current_subscription_expires: 1.day.ago)
      assert user.is_premium
      assert user.premium_or_supreme?
    end
  end

  %w[premium supreme].product(%w[mensual trimestral semestral]).each do |level, term|
    test "legacy product #{level} #{term} changes level without validating receipt" do
      user = User.create!(email: 'legacy@example.com', password: 'Secure123!')
      product = "toppin_#{level}_#{term}"
      Purchase.create!(user: user, product_id: product, receipt: nil, validated: false)
      assert_equal level, user.reload.current_subscription_name
      assert_equal product, user.current_subscription_id
      assert_nil user.current_subscription_expires
    end
  end
end
