# frozen_string_literal: true

require 'mailersend-ruby'

# Delivery method personalizado para integrar MailerSend con ActionMailer
class MailersendDeliveryMethod
  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    return if ENV['MAILERSEND_API_TOKEN'].blank?

    ms_email = Mailersend::Email.new

    # Configurar remitente
    from_email = mail.from&.first || ENV['MAILERSEND_FROM_EMAIL'] || 'noreply@tudominio.com'
    from_name = mail[:from]&.display_names&.first || ENV['MAILERSEND_FROM_NAME'] || 'Toppin'
    ms_email.add_recipients('from', from_email, from_name)

    # Configurar destinatarios
    if mail.to.present?
      mail.to.each do |to_email|
        to_name = mail[:to]&.display_names&.first || to_email
        ms_email.add_recipients('to', to_email, to_name)
      end
    end

    # CC
    if mail.cc.present?
      mail.cc.each do |cc_email|
        ms_email.add_recipients('cc', cc_email)
      end
    end

    # BCC
    if mail.bcc.present?
      mail.bcc.each do |bcc_email|
        ms_email.add_recipients('bcc', bcc_email)
      end
    end

    # Asunto
    ms_email.add_subject(mail.subject) if mail.subject.present?

    # Cuerpo del email (HTML y texto plano)
    if mail.html_part
      ms_email.add_html(mail.html_part.body.decoded)
    elsif mail.content_type&.include?('text/html')
      ms_email.add_html(mail.body.decoded)
    end

    if mail.text_part
      ms_email.add_text(mail.text_part.body.decoded)
    elsif mail.content_type&.include?('text/plain')
      ms_email.add_text(mail.body.decoded)
    end

    # Reply-To
    if mail.reply_to.present?
      ms_email.add_reply_to(mail.reply_to.first)
    end

    # Archivos adjuntos
    if mail.attachments.present?
      mail.attachments.each do |attachment|
        content = Base64.strict_encode64(attachment.body.decoded)
        ms_email.add_attachment(content, attachment.filename, 'attachment')
      end
    end

    # Enviar email
    ms_emails = Mailersend::Emails.new
    response = ms_emails.send(ms_email)

    # Logging
    if response.code == 202
      Rails.logger.info "Email enviado exitosamente a #{mail.to.join(', ')} - ID: #{response['x-message-id']}"
    else
      Rails.logger.error "Error enviando email a #{mail.to.join(', ')}: #{response.code} - #{response.body}"
      raise "MailerSend error: #{response.body}"
    end

    response
  rescue StandardError => e
    Rails.logger.error "Error en MailersendDeliveryMethod: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end

# Registrar el método de entrega con ActionMailer
ActionMailer::Base.add_delivery_method(:mailersend, MailersendDeliveryMethod)
