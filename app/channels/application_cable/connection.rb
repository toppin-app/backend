module ApplicationCable
  class Connection < ActionCable::Connection::Base
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
          user_id = decoded_token[0]['sub']
          return User.find(user_id)
        rescue JWT::DecodeError, ActiveRecord::RecordNotFound
          reject_unauthorized_connection
        end
      end

      reject_unauthorized_connection
    end
  end
end
