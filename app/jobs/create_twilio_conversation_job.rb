class CreateTwilioConversationJob < ApplicationJob
  queue_as :default

  def perform(match_request_id, user_id1, user_id2, send_message: false, message: nil)
    umr = UserMatchRequest.find_by(id: match_request_id)
    return unless umr # Si no existe, salir
    
    # Crear conversación de Twilio
    twilio = TwilioController.new
    conversation_sid = twilio.create_conversation(user_id1, user_id2)
    
    # Si es un sugar sweet, enviar mensaje
    if send_message && message.present?
      twilio.send_message_to_conversation(conversation_sid, user_id1, message)
    end
    
    # Actualizar el registro con el conversation_sid
    umr.update(twilio_conversation_sid: conversation_sid)
    
    Rails.logger.info "✅ Conversación de Twilio creada en background: #{conversation_sid}"
  rescue => e
    Rails.logger.error "❌ Error creando conversación de Twilio: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
