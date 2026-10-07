require 'test_helper'

class ConsumableRegenerationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    travel_to Time.zone.local(2026, 10, 7, 12)
  end

  teardown { travel_back }

  %w[premium supreme].each do |plan|
    { 0 => 5, 3 => 5, 5 => 5, 12 => 12 }.each do |balance, expected|
      test "weekly #{plan} balance #{balance} ends at #{expected}" do
        user = create_user(current_subscription_name: plan, superlike_available: balance)
        run_cron('/cron_regenerate_weekly_super_sweet')
        assert_equal expected, user.reload.superlike_available
        assert_equal Time.current, user.last_weekly_super_sweet_given
      end
    end
  end

  test 'free and unknown plans never receive paid weekly or monthly credits' do
    users = [nil, 'other'].map { |plan| create_user(current_subscription_name: plan, superlike_available: 0) }
    run_cron('/cron_regenerate_weekly_super_sweet')
    run_cron('/cron_regenerate_monthly_boost')
    users.each do |user|
      assert_equal 0, user.reload.superlike_available
      assert_equal 0, user.boost_available
      assert_nil user.last_weekly_super_sweet_given
      assert_nil user.last_monthly_boost_given
    end
  end

  test 'known expired and exactly expiring plans receive no paid credits from any cron' do
    users = %w[premium supreme].product([1.second.ago, Time.current]).map do |plan, expiry|
      create_user(current_subscription_name: plan, current_subscription_expires: expiry,
                  superlike_available: 0, last_superlike_given: 8.days.ago)
    end
    run_cron('/cron_regenerate_weekly_super_sweet')
    run_cron('/cron_regenerate_monthly_boost')
    run_cron('/users/cron_regenerate_superlike')
    users.each do |user|
      assert_equal 0, user.reload.superlike_available
      assert_equal 0, user.boost_available
    end
  end

  test 'active expiry and legacy unknown expiry still qualify for both paid benefits' do
    users = [nil, 1.second.from_now].map do |expiry|
      create_user(current_subscription_name: 'premium', current_subscription_expires: expiry, superlike_available: 0)
    end
    run_cron('/cron_regenerate_weekly_super_sweet')
    run_cron('/cron_regenerate_monthly_boost')
    users.each do |user|
      assert_equal 5, user.reload.superlike_available
      assert_equal 1, user.boost_available
    end
  end

  test 'legacy nil balances receive the weekly minimum and one monthly boost' do
    user = create_user(current_subscription_name: 'premium', superlike_available: nil, boost_available: nil)
    run_cron('/cron_regenerate_weekly_super_sweet')
    run_cron('/cron_regenerate_monthly_boost')
    assert_equal 5, user.reload.superlike_available
    assert_equal 1, user.boost_available
  end

  test 'weekly grant is independent of recent consumption' do
    user = create_user(current_subscription_name: 'premium', superlike_available: 2,
                       last_superlike_given: 1.minute.ago, last_weekly_super_sweet_given: 8.days.ago)
    run_cron('/cron_regenerate_weekly_super_sweet')
    assert_equal 5, user.reload.superlike_available
    assert_equal 1.minute.ago, user.last_superlike_given
  end

  test 'repeated calls and consumption do not refill within the same week' do
    user = create_user(current_subscription_name: 'supreme', superlike_available: 0)
    run_cron('/cron_regenerate_weekly_super_sweet')
    user.update_columns(superlike_available: 0, last_superlike_given: Time.current)
    run_cron('/cron_regenerate_weekly_super_sweet')
    run_cron('/users/cron_regenerate_superlike')
    assert_equal 0, user.reload.superlike_available
    assert_equal Time.current, user.last_weekly_super_sweet_given
  end

  test 'legacy and weekly routes share a single grant period' do
    user = create_user(current_subscription_name: 'premium', superlike_available: 0, last_superlike_given: 8.days.ago)
    run_cron('/users/cron_regenerate_superlike')
    assert_equal 5, user.reload.superlike_available
    assert_equal Time.current, user.last_weekly_super_sweet_given
    user.update_columns(superlike_available: 0)
    run_cron('/cron_regenerate_weekly_super_sweet')
    assert_equal 0, user.reload.superlike_available
  end

  test 'Madrid calendar week opens Monday even across a daylight saving change' do
    travel_to Time.zone.local(2026, 10, 25, 23, 59, 59)
    user = create_user(current_subscription_name: 'premium', superlike_available: 1,
                       last_weekly_super_sweet_given: Time.zone.local(2026, 10, 19))
    run_cron('/cron_regenerate_weekly_super_sweet')
    assert_equal 1, user.reload.superlike_available
    travel_to Time.zone.local(2026, 10, 26)
    run_cron('/cron_regenerate_weekly_super_sweet')
    assert_equal 5, user.reload.superlike_available
    user.update_columns(superlike_available: 1)
    run_cron('/cron_regenerate_weekly_super_sweet')
    assert_equal 1, user.reload.superlike_available
  end

  test 'monthly adds exactly one to bought balance once per Madrid calendar month' do
    user = create_user(current_subscription_name: 'premium', boost_available: 7,
                       last_monthly_boost_given: Time.zone.local(2026, 9, 1))
    run_cron('/cron_regenerate_monthly_boost')
    run_cron('/cron_regenerate_monthly_boost')
    assert_equal 8, user.reload.boost_available
    assert_equal Time.current, user.last_monthly_boost_given
    user.update_columns(boost_available: 0)
    travel_to Time.zone.local(2026, 10, 31, 23, 59, 59)
    run_cron('/cron_regenerate_monthly_boost')
    assert_equal 0, user.reload.boost_available
    travel_to Time.zone.local(2026, 11, 1)
    run_cron('/cron_regenerate_monthly_boost')
    assert_equal 1, user.reload.boost_available
  end

  test 'free legacy rolling refill keeps its existing quantity and cooldown' do
    due = create_user(superlike_available: 0, last_superlike_given: 7.days.ago)
    recent = create_user(superlike_available: 0, last_superlike_given: 6.days.ago)
    bought = create_user(superlike_available: 12, last_superlike_given: 8.days.ago)
    never_used = create_user(superlike_available: 0)
    run_cron('/users/cron_regenerate_superlike')
    assert_equal 1, due.reload.superlike_available
    assert_equal 0, recent.reload.superlike_available
    assert_equal 12, bought.reload.superlike_available
    assert_equal 0, never_used.reload.superlike_available
  end

  test 'free rolling cooldown remains 168 elapsed hours after autumn daylight saving' do
    travel_to Time.zone.local(2026, 10, 26)
    due = create_user(superlike_available: 0, last_superlike_given: Time.zone.local(2026, 10, 19, 0, 30))
    run_cron('/users/cron_regenerate_superlike')
    assert_equal 1, due.reload.superlike_available
  end

  test 'free rolling cooldown does not shorten after spring daylight saving' do
    travel_to Time.zone.local(2026, 3, 30)
    recent = create_user(superlike_available: 0, last_superlike_given: Time.zone.local(2026, 3, 22, 23, 30))
    run_cron('/users/cron_regenerate_superlike')
    assert_equal 0, recent.reload.superlike_available
  end

  test 'paid grants advance updated_at and repeated calls preserve that timestamp' do
    user = create_user(current_subscription_name: 'premium', superlike_available: 12)
    user.update_columns(updated_at: 1.day.ago)
    run_cron('/cron_regenerate_weekly_super_sweet')
    assert_equal Time.current, user.reload.updated_at
    travel_to Time.zone.local(2026, 10, 7, 13)
    run_cron('/cron_regenerate_monthly_boost')
    assert_equal Time.current, user.reload.updated_at
    travel_to Time.zone.local(2026, 10, 7, 14)
    run_cron('/cron_regenerate_weekly_super_sweet')
    run_cron('/cron_regenerate_monthly_boost')
    assert_equal Time.zone.local(2026, 10, 7, 13), user.reload.updated_at
  end

  test 'invalid token cannot regenerate any balance or marker' do
    user = create_user(current_subscription_name: 'premium', superlike_available: 0)
    ['/cron_regenerate_weekly_super_sweet', '/cron_regenerate_monthly_boost', '/users/cron_regenerate_superlike'].each do |path|
      get path, params: { token: 'invalid' }
      assert_response :unauthorized
    end
    assert_equal 0, user.reload.superlike_available
    assert_equal 0, user.boost_available
    assert_nil user.last_weekly_super_sweet_given
    assert_nil user.last_monthly_boost_given
  end

  private

  def create_user(**attributes)
    User.create!({ email: "regeneration-#{SecureRandom.hex(6)}@example.com", password: 'Secure123!',
                   boost_available: 0 }.merge(attributes))
  end

  def run_cron(path)
    get path, params: { token: UsersController::CRON_TOKEN }
    assert_response :success
    assert_equal 'OK', JSON.parse(response.body)
  end
end
