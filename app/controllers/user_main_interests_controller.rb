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

def bulk_create(user_main_interests: nil)
  # 1. Tomamos los intereses desde el parámetro o desde el request
  interests = user_main_interests || params[:user_main_interests]

  # 2. Validamos que haya al menos 4 intereses seleccionados
  if interests.blank? || interests.size < 4
    # Si no hay al menos 4 intereses, devolvemos un error
    render json: { error: "Debes seleccionar al menos 4 intereses" }, status: :bad_request
    return
  end

  # 3. Aseguramos que al menos el primer interés tenga user_id
  unless interests.first[:user_id]
    render json: { error: "Falta el user_id en los intereses" }, status: :unprocessable_entity
    return
  end

  # 4. Eliminamos los intereses anteriores del usuario
  UserMainInterest.where(user_id: interests.first[:user_id]).destroy_all

  # 5. Creamos los nuevos intereses uno por uno
  @user_main_interests = interests.map do |interest|
    # Asegúrate de que interest sea un ActionController::Parameters o convierte con `to_h` si viene como Hash
    permitted_interest = interest.respond_to?(:permit) ? interest.permit(:user_id, :interest_id, :percentage, :name) : ActionController::Parameters.new(interest).permit(:user_id, :interest_id, :percentage, :name)
    
    UserMainInterest.create(permitted_interest)
  end

  # 6. Verificamos que todos se hayan guardado correctamente
  if @user_main_interests.all?(&:persisted?)
    render json: { message: "Intereses guardados correctamente" }, status: :ok
  else
    render json: { error: "Error al guardar uno o más intereses" }, status: :unprocessable_entity
  end
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
