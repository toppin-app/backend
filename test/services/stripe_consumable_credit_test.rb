require 'test_helper'
require 'minitest/mock'

class StripeConsumableCreditTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  # Real commits and separate connections are necessary to exercise row locks.
  self.use_transactional_tests = false

  setup do
    @user = User.create!(email: "credit-#{SecureRandom.hex(6)}@example.com", password: 'Secure123!', boost_available: 0)
    @purchase = PurchasesStripe.create!(user: @user, payment_id: "pi_#{SecureRandom.hex(6)}", product_key: 'power_sweet_A')
  end

  teardown do
    PurchasesStripe.where(user_id: @user.id).delete_all
    UserFilterPreference.where(user_id: @user.id).delete_all
    User.where(id: @user.id).delete_all
  end

  def credit(user: @user, product: 'power_sweet_A', payment_id: @purchase.payment_id)
    StripeConsumableCredit.call(payment_id: payment_id, user: user, product_key: product,
                               config: { field: :boost_available, increment_value: 1 })
  end

  test 'simultaneous deliveries credit only once across separate connections' do
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          credit
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    workers.each(&:value)
    assert_equal 1, @user.reload.boost_available
    assert_equal 'succeeded', @purchase.reload.status
  end

  test 'receipt failure rolls back the credit and the retry credits once' do
    @purchase.stub(:update!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      PurchasesStripe.stub(:where, [@purchase]) do
        assert_raises(ActiveRecord::RecordInvalid) { credit }
      end
    end
    assert_equal 0, @user.reload.boost_available
    assert_equal 'pending', @purchase.reload.status
    2.times { credit }
    assert_equal 1, @user.reload.boost_available
  end

  test 'missing purchase is retryable and never credited without a receipt' do
    assert_raises(ActiveRecord::RecordNotFound) { credit(payment_id: 'pi_unknown') }
    assert_equal 0, @user.reload.boost_available
  end

  test 'mismatched customer cannot receive the purchase' do
    assert_raises(ArgumentError) { credit(user: nil) }
    assert_equal 'pending', @purchase.reload.status
    assert_equal 0, @user.reload.boost_available
  end

  test 'mismatched product cannot receive the purchase' do
    assert_raises(ArgumentError) { credit(product: 'power_sweet_C') }
    assert_equal 'pending', @purchase.reload.status
    assert_equal 0, @user.reload.boost_available
  end

  test 'duplicate legacy receipt rows still grant one credit' do
    second = PurchasesStripe.create!(user: @user, payment_id: @purchase.payment_id, product_key: 'power_sweet_A')
    2.times { credit }
    assert_equal 1, @user.reload.boost_available
    assert_equal 'succeeded', @purchase.reload.status
    assert_equal 'succeeded', second.reload.status
  end

  test 'previously failed payment can succeed once after another attempt' do
    @purchase.update!(status: 'failed')
    2.times { credit }
    assert_equal 1, @user.reload.boost_available
    assert_equal 'succeeded', @purchase.reload.status
  end
end
