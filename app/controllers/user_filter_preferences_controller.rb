class UserFilterPreferencesController < ApplicationController
  before_action :set_user_filter_preference, only: %i[ show edit update destroy ]

  # GET /user_filter_preferences or /user_filter_preferences.json
  def index
    @user_filter_preferences = UserFilterPreference.all
  end


  # Método que devuelve los filtros de un usuario.
  def get_user_filter_preferences
    @user_filter_preference = current_user.user_filter_preference
    render 'show'
  end

  # GET /user_filter_preferences/1 or /user_filter_preferences/1.json
  def show
  end

  # GET /user_filter_preferences/new
  def new
    @user_filter_preference = UserFilterPreference.new
  end

  # GET /user_filter_preferences/1/edit
  def edit
  end

  # POST /user_filter_preferences or /user_filter_preferences.json
  def create

    UserFilterPreference.where(user_id: params[:user_id]).destroy_all

    @user_filter_preference = UserFilterPreference.new(user_filter_preference_params)

    @user_filter_preference.interests = params[:interests].to_json
    @user_filter_preference.categories = params[:categories].to_json


    respond_to do |format|
      if @user_filter_preference.save

        format.html { redirect_to @user_filter_preference, notice: "User filter preference was successfully created." }
        format.json { render :show, status: :created, location: @user_filter_preference }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_filter_preference.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_filter_preferences/1 or /user_filter_preferences/1.json
  def update
    respond_to do |format|
      if @user_filter_preference.update(user_filter_preference_params)
        format.html { redirect_to @user_filter_preference, notice: "User filter preference was successfully updated." }
        format.json { render :show, status: :ok, location: @user_filter_preference }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_filter_preference.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_filter_preferences/1 or /user_filter_preferences/1.json
  def destroy
    @user_filter_preference.destroy
    respond_to do |format|
      format.html { redirect_to user_filter_preferences_url, notice: "User filter preference was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_filter_preference
      @user_filter_preference = UserFilterPreference.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_filter_preference_params
      params.require(:user_filter_preference).permit(:user_id, :gender, :distance_range, :age_from, :age_till, :only_verified_users, :interests, :categories)
    end
end
