require 'test_helper'
require 'minitest/mock'
require 'timeout'

class ConsumableRegenerationConcurrencyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  self.use_transactional_tests = false

  setup do
    travel_to Time.zone.local(2026, 10, 7, 12)
    @user = User.create!(email: "regeneration-race-#{SecureRandom.hex(6)}@example.com", password: 'Secure123!',
                         current_subscription_name: 'premium', superlike_available: 12, boost_available: 7)
  end

  teardown do
    PurchasesStripe.where(user_id: @user.id).delete_all
    UserFilterPreference.where(user_id: @user.id).delete_all
    User.where(id: @user.id).delete_all
    travel_back
  end

  test 'two monthly cron requests waiting on the same row grant only one boost' do
    while_cron_waits('/cron_regenerate_monthly_boost', workers: 2) { }
    assert_equal 8, @user.reload.boost_available
    assert_equal Time.current, @user.last_monthly_boost_given
  end

  test 'weekly request rechecks the grant period after waiting for a row lock' do
    while_cron_waits('/cron_regenerate_weekly_super_sweet') do
      @user.update_columns(superlike_available: 0, last_weekly_super_sweet_given: Time.current)
    end
    assert_equal 0, @user.reload.superlike_available
    assert_equal Time.current, @user.last_weekly_super_sweet_given
  end

  test 'weekly and legacy requests waiting together cannot refill a completed weekly grant' do
    @user.update_columns(superlike_available: 0, last_superlike_given: 8.days.ago)
    while_cron_waits(['/cron_regenerate_weekly_super_sweet', '/users/cron_regenerate_superlike']) do
      @user.update_columns(last_weekly_super_sweet_given: Time.current)
    end
    assert_equal 0, @user.reload.superlike_available
  end

  test 'monthly request rechecks the grant period after waiting for a row lock' do
    while_cron_waits('/cron_regenerate_monthly_boost') do
      @user.update_columns(boost_available: 0, last_monthly_boost_given: Time.current)
    end
    assert_equal 0, @user.reload.boost_available
    assert_equal Time.current, @user.last_monthly_boost_given
  end

  test 'weekly grant preserves a paid Stripe credit committed while the cron waits' do
    purchase = create_purchase('super_sweet_C')
    while_cron_waits('/cron_regenerate_weekly_super_sweet') do
      StripeConsumableCredit.call(payment_id: purchase.payment_id, user: @user, product_key: 'super_sweet_C',
                                 config: { field: :superlike_available, increment_value: 60 })
    end
    assert_equal 72, @user.reload.superlike_available
    assert_equal 'succeeded', purchase.reload.status
  end

  test 'monthly grant preserves a paid Stripe credit committed while the cron waits' do
    purchase = create_purchase('power_sweet_C')
    while_cron_waits('/cron_regenerate_monthly_boost') do
      StripeConsumableCredit.call(payment_id: purchase.payment_id, user: @user, product_key: 'power_sweet_C',
                                 config: { field: :boost_available, increment_value: 10 })
    end
    assert_equal 18, @user.reload.boost_available
    assert_equal 'succeeded', purchase.reload.status
  end

  ['/cron_regenerate_weekly_super_sweet', '/cron_regenerate_monthly_boost', '/users/cron_regenerate_superlike'].each do |path|
    test "#{path} rechecks expiration after waiting for a row lock" do
      @user.update_columns(superlike_available: 0, last_superlike_given: 8.days.ago)
      while_cron_waits(path) { @user.update_columns(current_subscription_expires: 1.second.ago) }
      assert_equal 0, @user.reload.superlike_available
      assert_equal 7, @user.boost_available
      assert_nil @user.last_weekly_super_sweet_given
      assert_nil @user.last_monthly_boost_given
    end
  end

  test 'monthly request rechecks cancellation after waiting for a row lock' do
    while_cron_waits('/cron_regenerate_monthly_boost') { @user.update_columns(current_subscription_name: nil) }
    assert_equal 7, @user.reload.boost_available
    assert_nil @user.last_monthly_boost_given
  end

  ['/cron_regenerate_weekly_super_sweet', '/cron_regenerate_monthly_boost'].each do |path|
    test "#{path} preserves a newer updated_at committed while waiting for a row lock" do
      while_cron_waits(path) { @user.update_columns(updated_at: 1.minute.from_now) }
      assert_equal 1.minute.from_now, @user.reload.updated_at
    end
  end

  private

  def create_purchase(product_key)
    PurchasesStripe.create!(user: @user, payment_id: "pi_#{SecureRandom.hex(6)}", product_key: product_key)
  end

  # Only inserts a barrier immediately before the real SQL write. Both HTTP
  # requests and Stripe receipts keep their real code and MySQL transactions.
  def while_cron_waits(path, workers: 1)
    paths = Array(path) * workers
    ready = Queue.new
    threads = []
    owner_connection_id = ActiveRecord::Base.connection.select_value('SELECT CONNECTION_ID()')
    @user.with_lock do
      threads = paths.map do |request_path|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            original = connection.method(:exec_update)
            announced = false
            connection_id = connection.select_value('SELECT CONNECTION_ID()')
            connection.stub(:exec_update, lambda { |sql, *args|
              paid_write = sql.include?('last_weekly_super_sweet_given') || sql.include?('boost_available') ||
                           sql.include?('IS NOT NULL') || sql.split(' WHERE ').first.include?('last_superlike_given')
              write_ids = sql.scan(/`users`\.`id`\s*=\s*(\d+)/).flatten
              targets_owner = write_ids.empty? || write_ids.include?(@user.id.to_s)
              if !announced && sql.start_with?('UPDATE `users`') && paid_write && targets_owner
                announced = true
                ready << connection_id
              end
              original.call(sql, *args)
            }) do
              client = ActionDispatch::Integration::Session.new(Rails.application)
              client.get(request_path, params: { token: UsersController::CRON_TOKEN })
              assert_equal 200, client.response.status
            end
          end
        end
      end
      paths.length.times do
        worker_connection_id = Timeout.timeout(10) { ready.pop }
        assert_not_equal owner_connection_id, worker_connection_id
      end
      yield
    end
    threads.each { |thread| Timeout.timeout(15) { thread.value } }
  ensure
    threads.each { |thread| thread.kill if thread.alive? }
  end
end
