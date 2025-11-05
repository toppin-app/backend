class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Adjuntar el logo como inline attachment
    attachments.inline['logo-devise.png'] = File.read(Rails.root.join('app', 'assets', 'images', 'logo-devise.png'))
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
