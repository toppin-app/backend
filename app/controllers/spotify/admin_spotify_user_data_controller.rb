module Spotify
  class AdminSpotifyUserDataController < ApplicationController
    before_action :set_user
    before_action :set_spotify_user_datum, only: [:show, :edit, :update, :destroy]

    # GET /users/:user_id/admin_spotify_user_data
    def index
      @spotify_user_data = SpotifyUserDatum.where(user_id: @user.id)
      if @spotify_user_data.any?
        render :index
      else
        head :no_content
      end
    end

    # GET /users/:user_id/admin_spotify_user_data/:id
    def show
      render :show
    end

    # GET /users/:user_id/admin_spotify_user_data/new
    def new
      @spotify_user_datum = SpotifyUserDatum.new
      render :new
    end

    # GET /users/:user_id/admin_spotify_user_data/:id/edit
    def edit
      @spotify_user_datum = @user.spotify_user_data.find(params[:id])
    end

    # POST /users/:user_id/admin_spotify_user_data
    def create
      @spotify_user_datum = SpotifyUserDatum.new(spotify_user_datum_params.merge(user_id: @user.id))
      if @spotify_user_datum.save
        redirect_to user_admin_spotify_user_datum_path(@user, @spotify_user_datum), notice: 'Spotify user data was successfully created.'
      else
        render :new
      end
    end

    # PATCH/PUT /users/:user_id/admin_spotify_user_data/:id
    def update
      @spotify_user_datum = @user.spotify_user_data.find(params[:id])
      if @spotify_user_datum.update(spotify_user_datum_params)
        redirect_to user_admin_spotify_user_datum_path(@user, @spotify_user_datum), notice: 'Spotify user data was successfully updated.'
      else
        render :edit
      end
    end

    # DELETE /users/:user_id/admin_spotify_user_data/:id
    def destroy
      @spotify_user_datum.destroy
      redirect_to user_admin_spotify_user_data_path(@user), notice: 'Spotify user data was successfully destroyed.'
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end

    def set_spotify_user_datum
      @spotify_user_datum = SpotifyUserDatum.find(params[:id])
    end

    def spotify_user_datum_params
      params.require(:spotify_user_datum).permit(:artist_name, :image, :preview_url, :track_name) # Asegúrate de que estos son los atributos correctos
    end
  end
end
