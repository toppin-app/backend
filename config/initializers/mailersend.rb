# frozen_string_literal: true

# Configuración de MailerSend
# Para usar MailerSend, necesitas un API Token desde: https://www.mailersend.com/
# Settings → API Tokens

require 'mailersend-ruby'

if ENV['MAILERSEND_API_TOKEN'].present?
  # Configurar cliente de MailerSend
  Mailersend::Client.configure do |config|
    config.api_key = ENV['MAILERSEND_API_TOKEN']
    # config.debug = Rails.env.development? # Descomentar para debug
  end
  
  Rails.logger.info "MailerSend configurado correctamente"
else
  Rails.logger.warn "MAILERSEND_API_TOKEN no está configurado. Los emails no se enviarán."
end
