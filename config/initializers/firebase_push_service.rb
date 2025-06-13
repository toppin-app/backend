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

  def send_notification(token:, title:, body:, data: {}, sound: "default", image: nil)
        payload = {
          message: {
            token: token,
            notification: {
              title: title,
              body: body,
              image: image
            },
            data: data.transform_keys(&:to_s), # Asegúrate de que las claves sean strings
            android: {
              notification: {
                sound: sound,
                image: image
              }
            },
            apns: {
              payload: {
                aps: {
                  sound: sound,
                  image: image  
                }
              }
            }
          }
        }

    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "application/json"
    }

    response = HTTParty.post(FCM_ENDPOINT, headers: headers, body: payload.to_json)

    Rails.logger.info "FCM Response: #{response.code} - #{response.body}"
    response
  end
end
