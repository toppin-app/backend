class Admin::UserMatchRequestsController < ApplicationController
  before_action :check_admin

  def index
    @user_match_requests = UserMatchRequest.all.order(created_at: :desc)
  end

  def destroy
    @user_match_request = UserMatchRequest.find(params[:id])
    @user_match_request.destroy
    redirect_to admin_user_match_requests_path, notice: 'Solicitud de match eliminada con éxito.'
  end
end