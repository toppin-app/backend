require 'base64'

class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Cargar el logo desde public
    logo_path = Rails.root.join('public', 'logo-devise.png')
    logo_content = File.binread(logo_path)
    @logo_base64 = Base64.strict_encode64(logo_content)
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
