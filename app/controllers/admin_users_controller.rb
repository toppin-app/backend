class Admin::UsersController < ApplicationController
  before_action :check_admin

  def create_match
    umr = UserMatchRequest.find(params[:id])
    umr.update(is_match: true, match_date: DateTime.now, user_ranking: umr.user.ranking, target_user_ranking: umr.target.ranking)
    conversation_sid = TwilioController.new.create_conversation(umr.user_id, umr.target_user)
    umr.update(twilio_conversation_sid: conversation_sid)
    redirect_to show_user_path(id: umr.target_user), notice: 'Match generado con éxito.'
  end

  def create_like
    umr = UserMatchRequest.find_or_create_by(user_id: params[:user_id], target_user: params[:target_user]) do |request|
      request.is_like = true
      request.is_rejected = false
      request.is_superlike = false
    end
    Thread.new do
      Device.sendIndividualPush(umr.target_user, "¡Wow! Tienes nuevos admiradores :-)", "Has recibido nuevos me gusta", "like", nil, "push_likes")
    end
    redirect_to show_user_path(id: umr.user_id), notice: 'Like generado con éxito.'
  end
end