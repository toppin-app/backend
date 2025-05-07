class UserLikesController < ApplicationController
  def create_like
    umr = UserMatchRequest.find_or_create_by(user_id: params[:user_id], target_user: params[:target_user]) do |request|
      request.is_like = true
      request.is_rejected = false
      request.is_superlike = false
    end
    Thread.new do
      Device.sendIndividualPush(umr.target_user, "¡Wow! Tienes nuevos admiradores :-)", "Has recibido nuevos me gusta", "like", nil, "push_likes")
    end
    redirect_to user_match_request_path(umr), notice: 'Like generado con éxito.'
  end

  def index
    @likes = UserMatchRequest.where(is_like: true)
  end
end