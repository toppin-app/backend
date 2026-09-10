class Users::SessionsController < Devise::SessionsController
    prepend_before_action :require_no_authentication, only: [:new, :create]
    prepend_before_action :limit_login_attempts, only: :create
    skip_before_action :save_last_connection
    skip_before_action :check_if_user_blocked
    #skip_before_action :verify_authenticity_token, :only => [:create, :new]


    respond_to :json, :html
    layout "devise"



  # GET /resource/sign_in
=begin def new
    self.resource = resource_class.new(sign_in_params)
    clean_up_passwords(resource)
    yield resource if block_given?
    respond_with(resource, serialize_options(resource))
  end
=end



  # POST /resource/sign_in
    def create
      user_params = params.require(:user).permit(:email, :password)
      @user = User.find_by(email: user_params[:email])

      if @user && @user.valid_password?(user_params[:password])
        # Verificar si el usuario está bloqueado
        if @user.blocked
          error_response = {
            error: "Usuario bloqueado",
            blocked: true,
            status: 403
          }
          
          # Agregar block_reason_key si existe
          if @user.block_reason_key.present?
            error_response[:block_reason_key] = @user.block_reason_key
          end
          
          respond_to do |format|
            format.html { redirect_to new_user_session_path, alert: "Tu cuenta ha sido bloqueada." }
            format.json { render json: error_response, status: :forbidden }
          end
          return
        end
        
        set_flash_message!(:notice, :signed_in)
        sign_in(@user)

        if @user.twilio_sid.blank?
          twilio = TwilioController.new
          twilio.generate_user_in_twilio(@user.id)
        end

        devices = Device.where(user_id: @user.id)

        respond_to do |format|
          format.html { redirect_to root_path }
          format.json { render 'users/show', status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to new_user_session_path, alert: "Email o contraseña incorrectos." }
          format.json { render json: { error: "No such user; check the submitted email address", status: 400 }, status: 400 }
        end
      end
  end


    private

    def limit_login_attempts
      envelope = params[:user]
      email = envelope.respond_to?(:permit) ? envelope[:email] : nil
      retry_after = LoginAttemptLimiter.check(ip: request.remote_ip, email: email)
      return if retry_after <= 0

      response.headers['Retry-After'] = retry_after.to_s
      response.headers['Cache-Control'] = 'no-store'
      respond_to do |format|
        format.json do
          render json: { error: 'Too many login attempts. Please try again later.',
                         code: 'login_rate_limited', retry_after: retry_after }, status: :too_many_requests
        end
        format.html do
          render plain: 'Too many login attempts. Please try again later.', status: :too_many_requests
        end
      end
    end



    def respond_to_on_destroy
        head :no_content
    end
end
