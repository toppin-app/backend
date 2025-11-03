# frozen_string_literal: true

# Script de verificación de configuración de MailerSend
# Ejecutar con: rails runner scripts/check_mailersend_config.rb

puts "\n" + "="*70
puts "🔍 VERIFICACIÓN DE CONFIGURACIÓN DE MAILERSEND"
puts "="*70 + "\n"

errors = []
warnings = []

# 1. Verificar que la gema está instalada
begin
  require 'mailersend-ruby'
  puts "✅ Gema mailersend-ruby instalada correctamente"
rescue LoadError
  errors << "❌ Gema mailersend-ruby NO encontrada. Ejecuta: bundle install"
end

# 2. Verificar API Token
if ENV['MAILERSEND_API_TOKEN'].present?
  if ENV['MAILERSEND_API_TOKEN'] == 'your_mailersend_api_token_here'
    warnings << "⚠️  API Token es el valor por defecto. Configura tu token real en .env"
  else
    puts "✅ MAILERSEND_API_TOKEN configurado"
  end
else
  errors << "❌ MAILERSEND_API_TOKEN no está configurado en .env"
end

# 3. Verificar email de origen
if ENV['MAILERSEND_FROM_EMAIL'].present?
  if ENV['MAILERSEND_FROM_EMAIL'] == 'noreply@tudominio.com'
    warnings << "⚠️  FROM_EMAIL es el valor por defecto. Configura tu email verificado en .env"
  else
    email = ENV['MAILERSEND_FROM_EMAIL']
    domain = email.split('@').last
    puts "✅ MAILERSEND_FROM_EMAIL configurado: #{email}"
    puts "   📧 Dominio: #{domain}"
    puts "   ⚠️  IMPORTANTE: Verifica que #{domain} esté verificado en MailerSend"
  end
else
  errors << "❌ MAILERSEND_FROM_EMAIL no está configurado en .env"
end

# 4. Verificar nombre del remitente
if ENV['MAILERSEND_FROM_NAME'].present?
  puts "✅ MAILERSEND_FROM_NAME configurado: #{ENV['MAILERSEND_FROM_NAME']}"
else
  warnings << "⚠️  MAILERSEND_FROM_NAME no configurado (se usará email como nombre)"
end

# 5. Verificar host por defecto
if ENV['MAILERSEND_DEFAULT_URL_HOST'].present?
  puts "✅ MAILERSEND_DEFAULT_URL_HOST configurado: #{ENV['MAILERSEND_DEFAULT_URL_HOST']}"
else
  warnings << "⚠️  MAILERSEND_DEFAULT_URL_HOST no configurado"
end

# 6. Verificar configuración de ActionMailer
puts "\n📬 Configuración de ActionMailer:"
puts "   Delivery method: #{ActionMailer::Base.delivery_method}"
if ActionMailer::Base.delivery_method == :mailersend
  puts "   ✅ Configurado para usar MailerSend"
else
  errors << "❌ ActionMailer no está configurado para usar :mailersend"
end

# 7. Verificar que el delivery method personalizado está cargado
if defined?(MailersendDeliveryMethod)
  puts "✅ MailersendDeliveryMethod cargado correctamente"
else
  errors << "❌ MailersendDeliveryMethod no está cargado"
end

# 8. Verificar ApplicationMailer
default_from = ApplicationMailer.default[:from]
puts "\n📨 ApplicationMailer configurado con:"
puts "   From: #{default_from}"

# Mostrar warnings
if warnings.any?
  puts "\n" + "⚠️ "*35
  puts "ADVERTENCIAS:"
  warnings.each { |w| puts w }
end

# Mostrar errores
if errors.any?
  puts "\n" + "❌ "*35
  puts "ERRORES CRÍTICOS:"
  errors.each { |e| puts e }
  puts "\n❌ La configuración tiene errores. Por favor corrígelos antes de continuar."
  puts "="*70 + "\n"
  exit 1
end

# Si todo está bien
if errors.empty? && warnings.empty?
  puts "\n" + "🎉 "*35
  puts "¡TODO PERFECTO! La configuración está completa."
  puts "\n📝 Siguiente paso: Probar enviando un email de prueba"
  puts "   rails console"
  puts "   TestMailer.welcome_email('tu-email@ejemplo.com').deliver_now"
elsif errors.empty?
  puts "\n✅ Configuración básica completada (pero revisa las advertencias)"
  puts "\n📝 Siguiente paso: Probar enviando un email de prueba"
  puts "   rails console"
  puts "   TestMailer.welcome_email('tu-email@ejemplo.com').deliver_now"
end

puts "="*70 + "\n"
