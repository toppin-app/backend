class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :destroy, :block]
  before_action :check_admin, only: [:index, :new, :edit]
  skip_before_action :verify_authenticity_token, only: [:show, :edit, :update, :destroy, :block]

  def index
    @title = "Lista de usuarios"
    @search = params.dig(:q, :email_or_name_cont) || ""
    @q = User.all.ransack(params[:q])
    @users = @q.result.order("created_at DESC").paginate(page: params[:page], per_page: 15)
  end

  def show
    @user = current_user.admin? ? User.find(params[:id]) : current_user
    @title = "Mostrando usuario"
    @matches = @user.matches
    @likes = @user.incoming_likes.order(id: :desc)
  end

  def new
    @user = User.new
    @title = "Crear nuevo usuario"
    @route = "/create_user"
  end

  def edit
    @title = "Editando usuario"
    @images = @user.user_media
    @edit = true
    @route = "/update_user"
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to @user, notice: 'User was successfully created.'
    else
      render :new
    end
  end

  def update
    @user = params[:id] ? User.find(params[:id]) : User.find(params[:user][:id])
    if @user.update(user_params)
      handle_associated_data
      redirect_to show_user_path(id: @user.id), notice: 'User was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @user.destroy
    redirect_to users_url, notice: 'Usuario eliminado con éxito.'
  end

  def block
    @user.blocked = !@user.blocked
    if @user.save
      redirect_to @user, notice: 'User was successfully blocked.'
    else
      render :edit
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation, :username, :blocked, :current_subscription_id, :show_publi, :current_subscription_name, :phone, :phone_validated, :verified, :verification_file, :push_token, :device_id, :device_platform, :description, :gender, :high_visibility, :hidden_by_user, :is_connected, :last_connection, :last_match, :is_new, :activity_level, :birthday, :born_in, :living_in, :locality, :country, :lat, :lng, :occupation, :studies, :popularity, user_media: [:id, :file, :position])
  end

  def handle_associated_data
    # Manejo de imágenes, intereses, y preferencias
    if params[:user][:images]
      params[:user][:images].each { |image| UserMedium.create(file: image, user_id: @user.id) }
    end
    if params[:info_item_values]
      params[:info_item_values].each { |iv| @user.user_info_item_values.create(info_item_value_id: iv) unless iv.blank? }
    end
    @user.user_filter_preference&.update(distance_range: params[:distance_range]) if params[:distance_range]
    @user.user_filter_preference&.update(gender: params[:filter_gender]) if params[:filter_gender]
  end
end