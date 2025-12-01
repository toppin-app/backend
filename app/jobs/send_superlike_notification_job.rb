class SendSuperlikeNotificationJob < ApplicationJob
  queue_as :default

  def perform(match_request_id)
    umr = UserMatchRequest.find_by(id: match_request_id)
    return unless umr

    target_user = User.find_by(id: umr.target_user)
    return unless target_user

    devices = Device.where(user_id: target_user.id).where.not(token: [nil, ''])
    notification = NotificationLocalizer.for(user: umr.user, type: :super_like)
    
    devices.each do |device|
      FirebasePushService.new.send_notification(
        token: device.token,
        title: notification[:title],
        body: notification[:body],
        data: { action: "like", user_id: umr.user_id.to_s }
      )
    end
  rescue StandardError => e
    Rails.logger.error "Error sending superlike notification: #{e.message}"
  end
end
