class UserMainInterestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user_main_interest, only: %i[ show edit update destroy ]

  # GET /user_main_interests or /user_main_interests.json
  def index
    @user_main_interests = current_user.user_main_interests
    render json: @user_main_interests
  end

  # GET /user_main_interests/1 or /user_main_interests/1.json
  def show
    render json: @user_main_interest
  end

   # GET /user_main_interests/user/:user_id.json
  def user_data
    @user_data = UserMainInterest.where(user_id: params[:user_id])
    render json: @user_data
  end

  # POST /user_main_interests or /user_main_interests.json
  def create
    @user_main_interest = current_user.user_main_interests.new(user_main_interest_params)
    if @user_main_interest.save
      render json: @user_main_interest, status: :created, location: @user_main_interest
    else
      render json: @user_main_interest.errors, status: :unprocessable_entity
    end
  end

  # POST /user_main_interests/bulk_create.json
  def bulk_create
    interests = user_main_interests || params[:user_main_interests]
    return false unless interests

    # Borra los datos existentes para el user_id
    UserMainInterest.where(user_id: interests.first[:user_id]).destroy_all

    # Crea nuevos datos
    @user_main_interests = interests.map do |interest|
      UserMainInterest.create(interest.permit(:user_id, :interest_id, :percentage, :name))
    end

    if @user_main_interests.all?(&:persisted?)
      render json: { message: "Intereses guardados correctamente" }, status: :ok
    else
      render json: { error: "Error al guardar uno o más intereses" }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /user_main_interests/1 or /user_main_interests/1.json
  def update
    if @user_main_interest.update(user_main_interest_params)
      render json: @user_main_interest
    else
      render json: @user_main_interest.errors, status: :unprocessable_entity
    end
  end

  # DELETE /user_main_interests/1 or /user_main_interests/1.json
  def destroy
    @user_main_interest.destroy
    head :no_content
  end

  # DELETE /user_main_interests.json
  def destroy_all
    current_user.user_main_interests.destroy_all
    head :no_content
  end

  private
  def bulk_user_main_interests_params
    params.require(:_json).map do |param|
      param.permit(:user_id, :interest_id, :percentage, :name)
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_user_main_interest
    @user_main_interest = current_user.user_main_interests.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def user_main_interest_params
    params.require(:user_main_interest).permit(:user_id, :interest_id, :percentage, :name)
  end
end
