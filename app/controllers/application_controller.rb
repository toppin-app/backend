class ApplicationController < ActionController::Base

     protect_from_forgery with: :null_session, unless: -> { request.format.json? }
     respond_to :json, :html
     before_action :set_titles
     before_action :authenticate_user!
     before_action :save_last_connection
     before_action :log_request_params
     after_action :log_response_body

     def set_titles
    #  logger.info request.authorization.inspect
        @meta_title = APP_CONFIG["default_meta_title"]
     end


  def check_admin
        if current_user and !current_user.admin?
          sign_out current_user
          redirect_to root_path
        end
  end



   def save_last_connection
      if current_user 
          if current_user.last_connection.nil? or current_user.last_connection < DateTime.now-3.minutes
              current_user.update(last_connection: DateTime.now, is_connected: true)
          end
      end
   end

   # Loguear parámetros del request
   def log_request_params
      filtered_params = params.except(:controller, :action, :format).to_unsafe_h
      Rails.logger.info "📥 REQUEST PARAMS [#{controller_name}##{action_name}]: #{filtered_params.inspect}"
   rescue => e
      Rails.logger.error "Error logging request params: #{e.message}"
   end

   # Loguear el body de la respuesta
   def log_response_body
      if response.body.present? && response.content_type&.include?('json')
         body_preview = response.body.length > 1000 ? "#{response.body[0..1000]}... (truncated)" : response.body
         Rails.logger.info "📤 RESPONSE [#{controller_name}##{action_name}] Status: #{response.status}: #{body_preview}"
      else
         Rails.logger.info "📤 RESPONSE [#{controller_name}##{action_name}] Status: #{response.status} (non-JSON or empty)"
      end
   rescue => e
      Rails.logger.error "Error logging response: #{e.message}"
   end


   # Genera un token de acceso a twilio para usar desde el front
   def generate_access_token(user_id = nil)

         set_account
         identity = user_id

         # Create Chat grant for our token
         grant = Twilio::JWT::AccessToken::ChatGrant.new

         grant.service_sid = @service_sid

         # Create an Access Token
         token = Twilio::JWT::AccessToken.new(
           @account_sid,
           @api_key,
           @api_secret,
           [grant],
           identity: identity
         )

         # Generate the token
         @token = token.to_jwt

         

   end


   def set_account


      @account_sid = 'AC856674e42d06d3ad5e9e6715e653271f'
      auth_token = '1770aef21ce5a3dbc343da7306d0a392'

      @api_key = 'SK03de9902556ee40a7ae0328c579b63d6'
      @api_secret = 'LykO5m9us4EhvdudzMKtaNoz7lBXsUgi'

      # Required for conversations api
      @service_sid = 'IS3215a77e05c34d53a5629c1f67aa49ee'


      @client = Twilio::REST::Client.new(@account_sid, auth_token)


   end



end
