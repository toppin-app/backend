require 'test_helper'
require 'minitest/mock'

class LikeDeliveryJobsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @a = User.create!(email: 'job-a@example.com', password: 'Secure123!')
    @b = User.create!(email: 'job-b@example.com', password: 'Secure123!')
    @row = UserMatchRequest.create!(user: @a, target_user: @b.id, is_like: true)
    @calls = []
    calls = @calls
    @twilio = Object.new
    @twilio.define_singleton_method(:create_conversation) { |*args| calls << [:create, *args]; 'new-conversation' }
    @twilio.define_singleton_method(:send_message_to_conversation) { |*args| calls << [:message, *args] }
  end

  test 'deleted requests do not contact conversation or push providers' do
    @row.destroy!
    TwilioController.stub(:new, -> { flunk 'No conversation expected' }) do
      CreateTwilioConversationJob.perform_now(@row.id, @a.id, @b.id)
    end
    FirebasePushService.stub(:new, -> { flunk 'No push expected' }) do
      [SendLikeNotificationJob, SendSuperlikeNotificationJob, SendMatchNotificationJob].each do |job|
        job.perform_now(@row.id)
      end
    end
  end

  test 'conversation job saves provider ID and optionally sends sugar message' do
    TwilioController.stub(:new, @twilio) do
      CreateTwilioConversationJob.perform_now(@row.id, @a.id, @b.id, send_message: true, message: 'Hello')
    end
    assert_equal 'new-conversation', @row.reload.twilio_conversation_sid
    assert_equal [[:create, @a.id, @b.id], [:message, 'new-conversation', @a.id, 'Hello']], @calls
  end

  test 'empty sugar message is not sent' do
    TwilioController.stub(:new, @twilio) do
      CreateTwilioConversationJob.perform_now(@row.id, @a.id, @b.id, send_message: true, message: '')
    end
    assert_equal [[:create, @a.id, @b.id]], @calls
  end

  test 'unconfirmed match does not send a match push' do
    FirebasePushService.stub(:new, -> { flunk 'No push expected' }) do
      SendMatchNotificationJob.perform_now(@row.id)
    end
  end

  test 'KNOWN BUG replaying the conversation job creates a second conversation' do
    TwilioController.stub(:new, @twilio) do
      2.times { CreateTwilioConversationJob.perform_now(@row.id, @a.id, @b.id) }
    end
    assert_equal 2, @calls.count { |call| call.first == :create }
  end

  test 'KNOWN BUG rejected request still creates a conversation when queued job runs' do
    @row.update!(is_rejected: true)
    TwilioController.stub(:new, @twilio) do
      CreateTwilioConversationJob.perform_now(@row.id, @a.id, @b.id)
    end
    assert_equal [[:create, @a.id, @b.id]], @calls
  end

  test 'KNOWN BUG like push ignores disabled preferences and a subsequent rejection' do
    @b.update!(push_general: false, push_likes: false)
    @row.update!(is_like: false, is_rejected: true)
    Device.create!(user: @b, device_uid: 'test-device', token: 'test-token', so: 'ios')
    payloads = []
    provider = Object.new
    provider.define_singleton_method(:send_notification) { |**args| payloads << args }
    FirebasePushService.stub(:new, provider) { SendLikeNotificationJob.perform_now(@row.id) }
    assert_equal 1, payloads.size
    assert_equal 'test-token', payloads.first[:token]
  end
end
