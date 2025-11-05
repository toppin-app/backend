require 'base64'

class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Intentar cargar el logo desde app/assets/images
    logo_path = Rails.root.join('app', 'assets', 'images', 'logo-html.png')
    
    if File.exist?(logo_path)
      begin
        logo_content = File.binread(logo_path)
        @logo_base64 = Base64.strict_encode64(logo_content)
      rescue => e
        Rails.logger.error "Error leyendo logo: #{e.message}"
        @logo_base64 = nil
      end
    else
      Rails.logger.warn "Logo no encontrado en: #{logo_path}"
      @logo_base64 = nil
    end
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
