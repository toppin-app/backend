module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.params[:token]

      if token.present?
        begin
          puts Rails.application.credentials.devise.inspect
          # Ajusta aquí la clave según cómo tengas configurado devise-jwt o tu JWT
          jwt = token.start_with?('Bearer ') ? token.split(' ', 2).last : token
          secret_key = Rails.application.credentials.devise[:jwt_secret_key]
          decoded_token = JWT.decode(token, secret_key, true, algorithm: 'HS256')
          user_id = decoded_token[0]['sub'] # asumiendo que el user_id está en 'sub'
          return User.find(user_id)
          rescue JWT::DecodeError, ActiveRecord::RecordNotFound
          # Token inválido o usuario no encontrado
          reject_unauthorized_connection
        end
      end

      # Si no autenticó por ninguno, rechazamos
      reject_unauthorized_connection
    end
  end
end
