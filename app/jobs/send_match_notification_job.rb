class SendMatchNotificationJob < ApplicationJob
  queue_as :default

  def perform(match_request_id)
    umr = UserMatchRequest.find_by(id: match_request_id)
    return unless umr&.is_match # Solo enviar si es un match válido
    
    # Determinar quién recibe la notificación
    match_user = User.find_by(id: umr.user_id)
    return unless match_user
    
    devices = Device.where(user_id: match_user.id).where.not(token: [nil, ''])
    return if devices.empty?
    
    notification = NotificationLocalizer.for(user: match_user, type: :match)
    
    devices.each do |device|
      FirebasePushService.new.send_notification(
        token: device.token,
        title: notification[:title],
        body: notification[:body],
        data: { action: "match", user_id: umr.user_id.to_s },
        sound: "match.mp3",
        channel_id: "sms-channel",
        category: "match"
      )
    end
    
    Rails.logger.info "✅ Notificación de match enviada a usuario #{match_user.id}"
  rescue => e
    Rails.logger.error "❌ Error enviando notificación de match: #{e.message}"
  end
end
