class UserMatchActionsController < ApplicationController
  def create_match
    umr = UserMatchRequest.find(params[:id])
    umr.update(is_match: true, match_date: DateTime.now, user_ranking: umr.user.ranking, target_user_ranking: umr.target.ranking)
    conversation_sid = TwilioController.new.create_conversation(umr.user_id, umr.target_user)
    umr.update(twilio_conversation_sid: conversation_sid)
    redirect_to user_match_request_path(umr), notice: 'Match generado con éxito.'
  end

  def reject_match
    umr = UserMatchRequest.find(params[:id])
    umr.update(is_rejected: true)
    TwilioController.new.destroy_conversation(umr.twilio_conversation_sid) if umr.twilio_conversation_sid.present?
    redirect_to user_match_request_path(umr), notice: 'Match rechazado con éxito.'
  end
end