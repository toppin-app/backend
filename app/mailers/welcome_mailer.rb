require 'base64'

class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Adjuntar logo como inline attachment
    logo_path = Rails.root.join('app', 'assets', 'images', 'logo-html.png')
    
    if File.exist?(logo_path)
      attachments.inline['logo.png'] = File.read(logo_path)
      @logo_attached = true
    else
      @logo_attached = false
    end
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
