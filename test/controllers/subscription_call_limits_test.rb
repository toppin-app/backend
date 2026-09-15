require 'test_helper'
require 'minitest/mock'

class SubscriptionCallLimitsTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  [nil, 'premium', 'supreme', 'unknown'].product([nil, 'premium', 'supreme', 'unknown']).each do |caller_level, receiver_level|
    test "call allowance #{caller_level.inspect} with #{receiver_level.inspect}" do
      caller = User.new(id: 1, current_subscription_name: caller_level)
      receiver = User.new(id: 2, current_subscription_name: receiver_level)
      result = generate(caller, receiver, used: 120)
      unlimited = [caller_level, receiver_level].any? { |level| %w[premium supreme].include?(level) }
      assert_equal(unlimited ? 864000 : 60, result[:json][:time_left])
    end
  end

  test 'free allowance never becomes negative' do
    result = generate(User.new(id: 1), User.new(id: 2), used: 200)
    assert_equal 0, result[:json][:time_left]
  end

  test 'KNOWN BUG unrelated authenticated user receives token for premium pair' do
    outsider = User.new(id: 3)
    result = generate(User.new(id: 1, current_subscription_name: 'premium'), User.new(id: 2), actor: outsider)
    assert_equal 'test-token', result[:json][:token]
    assert_equal 864000, result[:json][:time_left]
  end

  test 'KNOWN BUG expired subscription gives extended call allowance' do
    caller = User.new(id: 1, current_subscription_name: 'premium', current_subscription_expires: 1.day.ago)
    assert_equal 864000, generate(caller, User.new(id: 2))[:json][:time_left]
  end

  private
  def generate(caller, receiver, used: 0, actor: caller)
    controller = VideoCallsController.new
    controller.stub(:current_user, actor) do
      controller.stub(:params, { caller_id: caller.id, receiver_id: receiver.id }) do
        User.stub(:find_by, ->(id:) { id == caller.id ? caller : receiver }) do
          UserMatchRequest.stub(:match_confirmed_between?, true) do
            VideoCall.stub(:duration, used) do
              controller.stub(:build_agora_token, ->(**) { 'test-token' }) do
                controller.stub(:render, ->(**options) { options }) { controller.generate_token }
              end
            end
          end
        end
      end
    end
  end
end
