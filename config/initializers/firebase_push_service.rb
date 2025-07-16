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
  def send_notification(token:, title:, body:, data: {}, sound: "default", category: nil, channel_id:)
    payload = {
      message: {
        token: token,
        data: data.transform_keys(&:to_s), # Custom data
        notification: {
          title: title,
          body: body
        },
        android: {
          notification: {
            sound: sound,
            channel_id: "sms-channel" # Asegúrate de que esta channelId esté registrada en tu app Android
          }
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: body
              },
              sound: sound,
              category: category || "default" # Notifee lo puede usar para mostrar acciones personalizadas
            }
          },
          headers: {
            "apns-priority": "10", # Alta prioridad, importante para background
            "apns-push-type": "alert" # Necesario en iOS 13+ para notificaciones visibles
          }
        }
      }
    }

    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "application/json"
    }
    response = HTTParty.post(FCM_ENDPOINT, headers: headers, body: payload.to_json)
    # Manejo de errores
    if response.code != 200
      Rails.logger.error "❌ FCM Error: Code=#{response.code}, Body=#{response.body}, Payload=#{payload.to_json}"
    else
      Rails.logger.info "✅ FCM Success: Code=#{response.code}, Body=#{response.body}"
    end

    response
  end

end