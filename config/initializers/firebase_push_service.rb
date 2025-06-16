require 'googleauth'
require 'httparty'

class FirebasePushService
  FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/toppin-456209/messages:send"

  def initialize
    scope = ['https://www.googleapis.com/auth/firebase.messaging']
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(Rails.root.join('config/toppin-firebase-adminsdk.json')),
      scope: scope
    )
    authorizer.fetch_access_token!
    @access_token = authorizer.access_token
  end

  def send_notification(token:, title:, body:, data: {}, sound: "default")
    payload = {
      message: {
        token: token,
        notification: {
          title: title,
          body: body
        },
        data: data.transform_keys(&:to_s), # Los datos personalizados son Strings en las claves
        android: {
          notification: {
            sound: sound
          }
        },
        apns: {
          # Este es el payload de APNS correcto, donde 'aps' y los datos personalizados van dentro de 'payload'
          payload: {
            aps: {
              alert: {
                title: title,
                body: body
              },
              sound: sound
            }
            # Si necesitas datos personalizados también en el payload de APNS (además de en el 'data' global de FCM),
            # los agregarías aquí, por ejemplo:
            # "custom_action": data[:action],
            # "custom_user_id": data[:user_id]
          }
        }
      }
    }
    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "application/json"
    }

    response = HTTParty.post(FCM_ENDPOINT, headers: headers, body: payload.to_json)

    # Mejorar el log para errores
    if response.code != 200
      Rails.logger.error "FCM Error (iOS): Code=#{response.code}, Body=#{response.body}, Payload=#{payload.to_json}"
    else
      Rails.logger.info "FCM Success (iOS): Code=#{response.code}, Body=#{response.body}"
    end
    response
  end
end