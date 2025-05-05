class AdminController < ApplicationController
  before_action :authenticate_user!
  
  def index
    check_admin
    @title = "Panel de control administración"
  end


  def test_conversation
    twilio = TwilioController.new
    UserMatchRequest.create(user_id: params[:user_1], target_user: params[:user_2])
    conv = twilio.create_conversation(params[:user_1], params[:user_2])
    render json: conv.to_json

  end

end
