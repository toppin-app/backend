module ApplicationCable
  class Connection < ActionCable::Connection::Base
    skip_before_action :verify_authenticity_token
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.params[:token]
      Rails.logger.info("🔐 Recibido token: #{token.inspect}")
      if token.present?
        begin
          jwt = token.start_with?('Bearer ') ? token.split(' ', 2).last : token
          secret_key = ENV['DEVISE_JWT_SECRET_KEY']
          Rails.logger.info("🔑 JWT secret key: #{secret_key.present? ? 'PRESENTE' : 'FALTA'}")
          secret_key ||= Rails.application.credentials.dig(:jwt, :secret_key)
          unless secret_key
            Rails.logger.error("JWT secret key not found in credentials")
            reject_unauthorized_connection
          end
          decoded_token = JWT.decode(jwt, secret_key, true, algorithm: 'HS256')
          Rails.logger.info("🪪 Token decodificado: #{decoded_token.inspect}")
          user_id = decoded_token[0]['sub']
          Rails.logger.info("🔎 Buscando usuario con ID: #{user_id}")
          return User.find(user_id)
        rescue JWT::DecodeError => e
          Rails.logger.error("❌ JWT Decode Error: #{e.message}")
          reject_unauthorized_connection
        rescue ActiveRecord::RecordNotFound
          Rails.logger.error("❌ Usuario no encontrado con ID: #{user_id}")
          reject_unauthorized_connection
        end
      end

      reject_unauthorized_connection
    end
  end
end
