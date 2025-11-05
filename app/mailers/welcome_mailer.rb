class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Leer y convertir logo a base64 para embederlo directamente
    logo_path = Rails.root.join('public', 'logo-devise.png')
    if File.exist?(logo_path)
      @logo_base64 = Base64.strict_encode64(File.read(logo_path))
    else
      @logo_base64 = nil
    end
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
