require 'test_helper'
require Rails.root.join('db/migrate/20261007120000_add_last_weekly_super_sweet_given_to_users')

class WeeklySuperSweetMarkerTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  setup do
    travel_to Time.zone.local(2026, 10, 7, 12)
    @migration = AddLastWeeklySuperSweetGivenToUsers.new
    @users = [nil, 1.minute.ago, 8.days.ago].map do |used_at|
      User.create!(email: "marker-migration-#{SecureRandom.hex(6)}@example.com", password: 'Secure123!',
                   current_subscription_name: 'premium', superlike_available: 2, boost_available: 7,
                   last_superlike_given: used_at)
    end
    @migration.migrate(:down)
    User.reset_column_information
  end

  teardown do
    unless ActiveRecord::Base.connection.column_exists?(:users, :last_weekly_super_sweet_given)
      @migration.migrate(:up)
    end
    User.reset_column_information
    ids = @users.map(&:id)
    UserFilterPreference.where(user_id: ids).delete_all
    User.where(id: ids).delete_all
    travel_back
  end

  test 'forward migration preserves old activity conservatively without changing balances or consumption' do
    @migration.migrate(:up)
    User.reset_column_information
    [nil, 1.minute.ago, 8.days.ago].zip(@users).each do |used_at, user|
      user.reload
      if used_at
        assert_equal used_at, user.last_weekly_super_sweet_given
        assert_equal used_at, user.last_superlike_given
      else
        assert_nil user.last_weekly_super_sweet_given
        assert_nil user.last_superlike_given
      end
      assert_equal 2, user.superlike_available
      assert_equal 7, user.boost_available
    end

    SubscriptionConsumableRegeneration.weekly
    assert_equal 5, @users[0].reload.superlike_available
    assert_equal 2, @users[1].reload.superlike_available
    assert_equal 5, @users[2].reload.superlike_available
    travel_to Time.zone.local(2026, 10, 12)
    SubscriptionConsumableRegeneration.weekly
    assert_equal 5, @users[1].reload.superlike_available
  end

  test 'reverse migration removes only the new marker and can migrate forward again' do
    assert_not ActiveRecord::Base.connection.column_exists?(:users, :last_weekly_super_sweet_given)
    assert ActiveRecord::Base.connection.column_exists?(:users, :last_superlike_given)
    assert_equal 7, @users[1].reload.boost_available
    assert_equal 2, @users[1].superlike_available
    assert_equal 1.minute.ago, @users[1].last_superlike_given
    @migration.migrate(:up)
    User.reset_column_information
    assert_equal 1.minute.ago, @users[1].reload.last_weekly_super_sweet_given
  end
end
