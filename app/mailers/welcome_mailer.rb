require 'base64'

class WelcomeMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @app_url = ENV['MAILJET_DEFAULT_URL_HOST'] || 'toppin.es'
    
    # Usar URL pública del logo en lugar de base64
    @logo_url = "https://#{@app_url}/logo-html.png"
    
    # Usar el idioma del usuario o el idioma por defecto
    # Convertir a minúsculas porque en BD está en mayúsculas (ES, EN, etc.)
    user_locale = @user.language&.downcase&.to_sym || I18n.default_locale
    
    I18n.with_locale(user_locale) do
      mail(
        to: @user.email,
        subject: t('welcome_mailer.subject')
      )
    end
  end
end
