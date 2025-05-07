class UserInteractionsController < ApplicationController
  def user_swipes
    if current_user.user_media.none?
      render json: { status: 405, message: "Debes completar tu perfil con al menos una foto para poder ver a otros usuarios." }, status: 405
      return
    end

    # Lógica de filtrado y priorización de usuarios
    service = UserSwipeService.new(current_user)
    @users = service.fetch_swipes
    render json: @users
  end

  def use_boost
    if current_user.high_visibility
      render json: { status: 406, error: "Ya tienes un power sweet activo" }, status: 406
    elsif current_user.use_boost
      render json: "OK".to_json
    else
      render json: { status: 405, error: "No te quedan power sweet" }, status: 405
    end
  end
end