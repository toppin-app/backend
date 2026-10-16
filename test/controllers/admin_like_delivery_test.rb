require 'test_helper'
require 'minitest/mock'
require 'stringio'

class AdminLikeDeliveryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @admin = User.create!(email: 'like-admin@example.com', password: 'Secure123!', admin: true)
    @sender = User.create!(email: 'like-sender@example.com', password: 'Secure123!')
    @target = User.create!(email: 'like-target@example.com', password: 'Secure123!')
    @device = Device.create!(user: @target, device_uid: 'admin-like-device', token: 'synthetic-device-token', so: 'ios')
    sign_in @admin
  end

  test 'OAuth authorization failure does not turn a saved like into a failed request' do
    log = StringIO.new
    error = Signet::AuthorizationError.new('invalid_grant: account not found; secret-sentinel')

    Rails.stub(:logger, ActiveSupport::Logger.new(log)) do
      FirebasePushService.stub(:new, -> { raise error }) do
        assert_difference('UserMatchRequest.count', 1) { submit_like }
      end
    end

    assert_like_saved
    assert_redirected_to show_user_path(id: @sender.id)
    assert_includes flash[:notice], 'Like generado'
    assert_includes flash[:alert], 'notificación'
    assert_includes log.string, 'Signet::AuthorizationError'
    assert_not_includes log.string, 'secret-sentinel'
    assert_not_includes log.string, 'synthetic-device-token'
  end

  test 'failed push delivery continues with the other device and preserves the like' do
    second = Device.create!(user: @target, device_uid: 'admin-like-device-2', token: 'second-device-token', so: 'ios')
    delivered = []
    provider = Object.new
    failed_token = @device.token
    provider.define_singleton_method(:send_notification) do |**payload|
      raise Timeout::Error, 'synthetic network failure' if payload[:token] == failed_token
      delivered << payload[:token]
    end

    FirebasePushService.stub(:new, provider) { submit_like }

    assert_like_saved
    assert_redirected_to show_user_path(id: @sender.id)
    assert_equal [second.token], delivered
    assert_includes flash[:alert], 'notificación'
  end

  test 'successful push keeps its payload and the normal confirmation' do
    payloads = []
    provider = Object.new
    provider.define_singleton_method(:send_notification) { |**payload| payloads << payload }

    FirebasePushService.stub(:new, provider) { submit_like }

    assert_like_saved
    assert_redirected_to show_user_path(id: @sender.id)
    assert_equal 'Like generado con éxito.', flash[:notice]
    assert_nil flash[:alert]
    assert_equal 1, payloads.size
    assert_equal @device.token, payloads.first.fetch(:token)
    assert_equal({ action: 'like', user_id: @sender.id.to_s }, payloads.first.fetch(:data))
    assert_equal 'sms.mp3', payloads.first.fetch(:sound)
    assert_equal 'sms-channel', payloads.first.fetch(:channel_id)
    assert payloads.first.fetch(:title).present?
    assert payloads.first.fetch(:body).present?
  end

  test 'users without notification tokens do not need Firebase to create a like' do
    # Legacy rows can lack a token even though new devices validate its presence.
    @device.update_column(:token, '')
    FirebasePushService.stub(:new, -> { flunk 'Firebase should not be contacted' }) { submit_like }

    assert_like_saved
    assert_redirected_to show_user_path(id: @sender.id)
    assert_nil flash[:alert]
  end

  test 'retry after an authorization error does not create a second like row' do
    FirebasePushService.stub(:new, -> { raise Signet::AuthorizationError, 'synthetic rejection' }) do
      assert_difference('UserMatchRequest.count', 1) { submit_like }
      assert_no_difference('UserMatchRequest.count') { submit_like }
    end

    assert_like_saved
    assert_redirected_to show_user_path(id: @sender.id)
  end

  test 'ordinary users still cannot submit administrative likes' do
    sign_out @admin
    sign_in @sender
    FirebasePushService.stub(:new, -> { flunk 'Unauthorized push' }) do
      assert_no_difference('UserMatchRequest.count') { submit_like }
    end
    assert_redirected_to root_path
  end

  private

  def submit_like
    post '/create_like', params: { user_id: @sender.id, target_user: @target.id }
  end

  def assert_like_saved
    like = UserMatchRequest.find_by!(user_id: @sender.id, target_user: @target.id)
    assert like.is_like
    assert_not like.is_rejected
    assert_not like.is_superlike
  end
end
