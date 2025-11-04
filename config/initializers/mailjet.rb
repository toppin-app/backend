# frozen_string_literal: true

# Configuración de Mailjet
# Para usar Mailjet, necesitas API Key y Secret Key desde: https://www.mailjet.com/
# Account Settings → REST API → API Key Management

# Cargar el delivery method personalizado
require_relative '../../lib/mailjet_delivery_method'

if ENV['MAILJET_API_KEY'].present? && ENV['MAILJET_SECRET_KEY'].present?
  Rails.logger.info "Mailjet: Credenciales configuradas correctamente"
else
  Rails.logger.warn "Mailjet: MAILJET_API_KEY o MAILJET_SECRET_KEY no están configurados. Los emails no se enviarán."
end
