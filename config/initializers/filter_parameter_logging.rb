# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from Rails logs.
Rails.application.config.filter_parameters += [
  :password,
  :password_confirmation,
  :authorization,
  :token,
  :access_token,
  :refresh_token,
  :id_token,
  :device_token,
  :fcm_token,
  :api_key,
  :api_secret,
  :client_secret,
  :private_key,
  :secret,
  :otp,
  :pin,
  :verification_code,
  /\Acode\z/,
  :recovery_code,
  :recovery_token,
  :new_password,
  :card_number,
  :credit_card,
  :cvv,
  :cvc
]
