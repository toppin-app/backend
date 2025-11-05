class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Adjuntar el logo como inline attachment para que se vea en el email
    logo_path = Rails.root.join('public', 'logo-devise.png')
    if File.exist?(logo_path)
      attachments.inline['logo-toppin.png'] = File.read(logo_path)
    end
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
