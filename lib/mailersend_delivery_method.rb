# frozen_string_literal: true

require 'httparty'
require 'json'

# Delivery method personalizado para integrar MailerSend con ActionMailer
# Usa la API REST de MailerSend directamente
class MailersendDeliveryMethod
  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    api_token = ENV['MAILERSEND_API_TOKEN']
    
    if api_token.blank?
      Rails.logger.error "MailerSend: API Token no configurado"
      raise "MailerSend API Token no está configurado en las variables de entorno"
    end

    # Preparar el payload para MailerSend API
    from_email = mail.from&.first || ENV['MAILERSEND_FROM_EMAIL'] || 'noreply@tudominio.com'
    from_name = ENV['MAILERSEND_FROM_NAME'] || 'Toppin'
    
    payload = {
      from: {
        email: from_email,
        name: from_name
      },
      to: [],
      subject: mail.subject || 'Sin asunto'
    }

    # Agregar destinatarios
    if mail.to.present?
      mail.to.each do |to_email|
        payload[:to] << { email: to_email }
      end
    end

    # CC
    if mail.cc.present?
      payload[:cc] = mail.cc.map { |email| { email: email } }
    end

    # BCC
    if mail.bcc.present?
      payload[:bcc] = mail.bcc.map { |email| { email: email } }
    end

    # Reply-To
    if mail.reply_to.present?
      payload[:reply_to] = {
        email: mail.reply_to.first
      }
    end

    # Contenido del email
    # Detectar si es multipart (HTML + texto) o simple
    if mail.multipart?
      # Email con HTML y texto
      payload[:text] = mail.text_part.body.decoded if mail.text_part
      payload[:html] = mail.html_part.body.decoded if mail.html_part
    else
      # Email simple
      if mail.content_type&.include?('text/html')
        payload[:html] = mail.body.decoded
      else
        payload[:text] = mail.body.decoded
      end
    end

    # Archivos adjuntos (si los hay)
    if mail.attachments.present?
      payload[:attachments] = []
      mail.attachments.each do |attachment|
        payload[:attachments] << {
          content: Base64.strict_encode64(attachment.body.decoded),
          filename: attachment.filename,
          disposition: 'attachment'
        }
      end
    end

    # Enviar a MailerSend API
    response = HTTParty.post(
      'https://api.mailersend.com/v1/email',
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_token}"
      },
      body: payload.to_json
    )

    # Verificar respuesta
    if response.code == 202
      Rails.logger.info "✓ Email enviado exitosamente a #{mail.to.join(', ')}"
      Rails.logger.info "  MailerSend Response: #{response.code}"
    else
      error_msg = "Error enviando email: #{response.code} - #{response.body}"
      Rails.logger.error "✗ #{error_msg}"
      raise "MailerSend error: #{response.body}"
    end

    response
  rescue StandardError => e
    Rails.logger.error "✗ Error en MailersendDeliveryMethod: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise e
  end
end

# Registrar el método de entrega con ActionMailer
ActionMailer::Base.add_delivery_method(:mailersend, MailersendDeliveryMethod)
