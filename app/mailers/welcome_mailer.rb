class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    mail(
      to: @user.email,
      subject: '¡Bienvenido a Toppin! 🍩'
    )
  end
end
