class Users::SessionsController < Devise::SessionsController
    prepend_before_action :require_no_authentication, only: [:new, :create]
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

  # raise auth_options.inspect
#   self.resource = warden.authenticate!(auth_options)

    @user = User.find_by(email: params[:user][:email])


    if @user and !@user.blocked and @user.valid_password?(params[:user][:password])
     set_flash_message!(:notice, :signed_in)
     sign_in(@user)

     if @user.twilio_sid.blank?
        twilio = TwilioController.new
        twilio.generate_user_in_twilio(@user.id)
     end


      respond_to do |format|
        format.html  { redirect_to root_path }
        # format.json  { render json: user.as_json }
        format.json  { render 'users/show' }
      end
     

    else
        render json: {
            error: "No such user; check the submitted email address",
            status: 400
          }, status: 400
    end

  end


    private



    def respond_to_on_destroy
        head :no_content
    end
end