class UserMatchRequestsController < ApplicationController
  before_action :set_user_match_request, only: [:show, :destroy]

  def index
    @user_match_requests = UserMatchRequest.all
  end

  def show
  end

  def destroy
    @user_match_request.destroy
    redirect_to user_match_requests_url, notice: 'Solicitud de match eliminada con éxito.'
  end

  private

  def set_user_match_request
    @user_match_request = UserMatchRequest.find(params[:id])
  end
end