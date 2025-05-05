class UserMediaController < ApplicationController
  before_action :set_user_medium, only: %i[ show edit update destroy ]

  # GET /user_media or /user_media.json
  def index
    @user_media = UserMedium.all
  end

  # GET /user_media/1 or /user_media/1.json
  def show
  end

  # GET /user_media/new
  def new
    @user_medium = UserMedium.new
  end

  # GET /user_media/1/edit
  def edit
  end

  # POST /user_media or /user_media.json
  def create
    @user_medium = UserMedium.new(user_medium_params)

    respond_to do |format|
      if @user_medium.save

        is_valid = @user_medium.user.detect_nudity

        format.html { redirect_to @user_medium, notice: "User medium was successfully created." }
        format.json { 
            if is_valid
              render json: { status: 200, message: "OK", image_data: @user_medium}, status: 200
            else
              @user_medium.destroy
              render json: {  status: 400, message: "La foto no pasa el proceso de verificación"}, status: 400
            end
         }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_medium.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_media/1 or /user_media/1.json
  def update
    respond_to do |format|
      if @user_medium.update(user_medium_params)
        format.html { redirect_to @user_medium, notice: "User medium was successfully updated." }
        format.json { render :show, status: :ok, location: @user_medium }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_medium.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_media/1 or /user_media/1.json
  def destroy
    user_id = @user_medium.user_id
    @user_medium.destroy
    respond_to do |format|
      format.html { redirect_to edit_user_path(id: user_id), notice: "Foto eliminada con éxito" }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_medium
      @user_medium = UserMedium.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_medium_params
      params.require(:user_medium).permit(:user_id, :file, :position)
    end
end
