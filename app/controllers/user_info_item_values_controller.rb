class UserInfoItemValuesController < ApplicationController
  before_action :set_user_info_item_value, only: %i[ show edit update destroy ]

  # GET /user_info_item_values or /user_info_item_values.json
  def index
    @user_info_item_values = UserInfoItemValue.all
  end

  # GET /user_info_item_values/1 or /user_info_item_values/1.json
  def show

  end

  # GET /user_info_item_values/new
  def new
    @user_info_item_value = UserInfoItemValue.new
  end

  # GET /user_info_item_values/1/edit
  def edit
  end

  # POST /user_info_item_values or /user_info_item_values.json
  def create
    @user_info_item_value = UserInfoItemValue.new(user_info_item_value_params)

    respond_to do |format|
      if @user_info_item_value.save
        format.html { redirect_to @user_info_item_value, notice: "User info item value was successfully created." }
        format.json { render :show, status: :created, location: @user_info_item_value }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_info_item_value.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_info_item_values/1 or /user_info_item_values/1.json
  def update
    respond_to do |format|
      if @user_info_item_value.update!(user_info_item_value_params)
        format.html { redirect_to @user_info_item_value, notice: "User info item value was successfully updated." }
        format.json { render :show, status: :ok, location: @user_info_item_value }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_info_item_value.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_info_item_values/1 or /user_info_item_values/1.json
  def destroy
    user = @user_info_item_value.user
    @user_info_item_value.destroy
    respond_to do |format|
      format.html { redirect_to edit_user_path(id: user.id), notice: "Eliminado con éxito" }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_info_item_value
      @user_info_item_value = UserInfoItemValue.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_info_item_value_params
      params.require(:user_info_item_value).permit(:user_id, :info_item_value_id)
    end
end
