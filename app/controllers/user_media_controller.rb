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
  image_file = params[:user_medium][:file]

  if image_file && current_user.detect_nudity(image_file)
    respond_to do |format|
      format.html { redirect_to user_media_url, alert: "La imagen contenía desnudos y no se ha subido." }
      format.json { render json: { status: 400, message: "La imagen contenía desnudos y no se ha subido." }, status: :bad_request }
    end
    return
  end

  @user_medium = UserMedium.new(user_medium_params)
  respond_to do |format|
    if @user_medium.save
      format.html { redirect_to @user_medium, notice: "User medium was successfully created." }
      format.json { render json: { status: :created, user_media: current_user.user_media }, status: :created }
    else
      format.html { render :new, status: :unprocessable_entity }
      format.json { render json: @user_medium.errors, status: :unprocessable_entity }
    end
  end
end

# PATCH/PUT /user_media/1 or /user_media/1.json
def update
  image_file = params[:user_medium][:file]

  respond_to do |format|
    if @user_medium.update(user_medium_params)
      if image_file && current_user.detect_nudity(image_file)
        @user_medium.remove_file!
        @user_medium.save
        format.html { redirect_to user_media_url, alert: "La imagen contenía desnudos y fue eliminada." }
        format.json { render json: { status: 400, message: "La imagen contenía desnudos y fue eliminada." }, status: :bad_request }
      else
        format.html { redirect_to @user_medium, notice: "User medium was successfully updated." }
        format.json { render :show, status: :ok, location: @user_medium }
      end
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
