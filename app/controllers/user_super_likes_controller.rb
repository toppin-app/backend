class UserSuperLikesController < ApplicationController
  def create_superlike
    umr = UserMatchRequest.find_or_create_by(user_id: params[:user_id], target_user: params[:target_user]) do |request|
      request.is_superlike = true
      request.is_like = false
      request.is_rejected = false
    end
    Thread.new do
      Device.sendIndividualPush(umr.target_user, "¡Wow! Tienes un superlike :-)", "Has recibido un superlike", "superlike", nil, "push_superlikes")
    end
    redirect_to user_match_request_path(umr), notice: 'Superlike generado con éxito.'
  end

  def index
    @superlikes = UserMatchRequest.where(is_superlike: true)
  end
end