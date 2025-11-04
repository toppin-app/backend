# frozen_string_literal: true

require 'mailjet'

# Delivery method personalizado para integrar Mailjet con ActionMailer
class MailjetDeliveryMethod
  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    api_key = ENV['MAILJET_API_KEY']
    secret_key = ENV['MAILJET_SECRET_KEY']
    
    if api_key.blank? || secret_key.blank?
      Rails.logger.error "Mailjet: API Key o Secret Key no configurados"
      raise "Mailjet API credentials no están configuradas en las variables de entorno"
    end

    # Configurar Mailjet
    Mailjet.configure do |config|
      config.api_key = api_key
      config.secret_key = secret_key
      config.api_version = 'v3.1'
    end

    # Preparar el payload para Mailjet API
    from_email = mail.from&.first || ENV['MAILJET_FROM_EMAIL'] || 'noreply@tudominio.com'
    from_name = ENV['MAILJET_FROM_NAME'] || 'Toppin'
    
    # Preparar destinatarios
    to_recipients = []
    if mail.to.present?
      mail.to.each do |to_email|
        to_recipients << {
          'Email' => to_email,
          'Name' => to_email.split('@').first
        }
      end
    end

    # Preparar CC
    cc_recipients = []
    if mail.cc.present?
      mail.cc.each do |cc_email|
        cc_recipients << {
          'Email' => cc_email,
          'Name' => cc_email.split('@').first
        }
      end
    end

    # Preparar BCC
    bcc_recipients = []
    if mail.bcc.present?
      mail.bcc.each do |bcc_email|
        bcc_recipients << {
          'Email' => bcc_email,
          'Name' => bcc_email.split('@').first
        }
      end
    end

    # Detectar contenido del email
    text_part = nil
    html_part = nil

    if mail.multipart?
      text_part = mail.text_part&.body&.decoded
      html_part = mail.html_part&.body&.decoded
    else
      if mail.content_type&.include?('text/html')
        html_part = mail.body.decoded
      else
        text_part = mail.body.decoded
      end
    end

    # Construir el mensaje
    message = {
      'From' => {
        'Email' => from_email,
        'Name' => from_name
      },
      'To' => to_recipients,
      'Subject' => mail.subject || 'Sin asunto'
    }

    # Añadir CC si existe
    message['Cc'] = cc_recipients if cc_recipients.any?
    
    # Añadir BCC si existe
    message['Bcc'] = bcc_recipients if bcc_recipients.any?

    # Añadir contenido
    message['TextPart'] = text_part if text_part.present?
    message['HTMLPart'] = html_part if html_part.present?

    # Reply-To
    if mail.reply_to.present?
      message['ReplyTo'] = {
        'Email' => mail.reply_to.first
      }
    end

    # Archivos adjuntos
    if mail.attachments.present?
      message['Attachments'] = []
      mail.attachments.each do |attachment|
        message['Attachments'] << {
          'ContentType' => attachment.content_type,
          'Filename' => attachment.filename,
          'Base64Content' => Base64.strict_encode64(attachment.body.decoded)
        }
      end
    end

    # Enviar el email
    response = Mailjet::Send.create(messages: [message])

    # Verificar respuesta
    if response.success?
      Rails.logger.info "✓ Email enviado exitosamente a #{mail.to.join(', ')}"
      Rails.logger.info "  Mailjet Response: #{response.attributes['Messages'].first['Status']}"
    else
      error_msg = "Error enviando email: #{response.attributes}"
      Rails.logger.error "✗ #{error_msg}"
      raise "Mailjet error: #{response.attributes}"
    end

    response
  rescue StandardError => e
    Rails.logger.error "✗ Error en MailjetDeliveryMethod: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise e
  end
end

# Registrar el método de entrega con ActionMailer
ActionMailer::Base.add_delivery_method(:mailjet, MailjetDeliveryMethod)
