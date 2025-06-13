class SendChatNotificationJob < ApplicationJob
  queue_as :default

  def perform(receiver_id, sender_id)
    receiver = User.find_by(id: receiver_id)
    sender = User.find_by(id: sender_id)
    return unless receiver && sender && receiver.push_chat

    return if receiver.current_conversation == UserMatchRequest.find_by(twilio_conversation_sid: params[:ChannelSid])&.twilio_conversation_sid

    notification = NotificationLocalizer.for(user: sender, type: :chat)
    devices = Device.where(user_id: receiver.id)

    devices.each do |device|
      next unless device.token.present?

      FirebasePushService.new.send_notification(
        token: device.token,
        title: notification[:title],
        body: notification[:body],
        data: { action: "chat", user_id: sender.id.to_s }
      )
    end
  end
end
