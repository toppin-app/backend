# frozen_string_literal: true

# Mailer de prueba para verificar que MailerSend funciona correctamente
# 
# Para probar en consola Rails:
#   TestMailer.welcome_email('tu-email@ejemplo.com').deliver_now
#
class TestMailer < ApplicationMailer
  def welcome_email(to_email)
    @recipient = to_email
    
    mail(
      to: to_email,
      subject: '¡Bienvenido a Toppin! - Email de prueba'
    )
  end
  
  def notification_email(to_email, subject, message)
    @message = message
    
    mail(
      to: to_email,
      subject: subject
    )
  end
end
