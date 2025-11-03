# frozen_string_literal: true

# Configuración de MailerSend
# Para usar MailerSend, necesitas un API Token desde: https://www.mailersend.com/
# Settings → API Tokens

# Cargar el delivery method personalizado
require_relative '../../lib/mailersend_delivery_method'

# La gema mailersend-ruby se configura automáticamente desde las variables de entorno
# No requiere configuración adicional aquí

if ENV['MAILERSEND_API_TOKEN'].present?
  Rails.logger.info "MailerSend: API Token configurado correctamente"
else
  Rails.logger.warn "MailerSend: MAILERSEND_API_TOKEN no está configurado. Los emails no se enviarán."
end
