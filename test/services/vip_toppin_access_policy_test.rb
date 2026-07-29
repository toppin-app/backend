require 'test_helper'

class VipToppinAccessPolicyTest < ActiveSupport::TestCase
  FakeUnlock = Struct.new(:target_id) do
    def persisted?
      true
    end
  end

  class FakeUnlocks
    attr_reader :target_ids

    def initialize
      @target_ids = []
    end

    def find_or_create_by(target_id:)
      @target_ids << target_id unless @target_ids.include?(target_id)
      FakeUnlock.new(target_id)
    end
  end

  FakeUser = Struct.new(:subscription, :user_vip_unlocks) do
    def premium_or_supreme?
      %w[premium supreme].include?(subscription)
    end
  end

  test 'premium users can unlock more than six distinct profiles' do
    unlocks = FakeUnlocks.new
    policy = VipToppinAccessPolicy.new(FakeUser.new('premium', unlocks))

    7.times { |index| assert policy.unlock(index + 1).persisted? }

    assert_equal 7, unlocks.target_ids.length
  end

  test 'supreme users have unlimited access too' do
    policy = VipToppinAccessPolicy.new(
      FakeUser.new('supreme', FakeUnlocks.new)
    )

    assert policy.unlimited_access?
  end

  test 'free users cannot unlock VIP profiles' do
    policy = VipToppinAccessPolicy.new(FakeUser.new(nil, FakeUnlocks.new))

    assert_not policy.unlimited_access?
    assert_nil policy.unlock(1)
  end
end
