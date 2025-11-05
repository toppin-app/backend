require 'base64'

class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Usar el asset pipeline para obtener la imagen
    logo_path = Rails.root.join('app', 'assets', 'images', 'logo-html.png')
    
    if File.exist?(logo_path)
      logo_content = File.binread(logo_path)
      @logo_base64 = Base64.strict_encode64(logo_content)
    else
      @logo_base64 = nil
    end
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
