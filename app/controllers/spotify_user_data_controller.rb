class SpotifyUserDataController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  before_action :set_spotify_user_datum, only: [:show, :update, :destroy]


  # GET /spotify_user_data.json
  def index
    @spotify_user_data = current_user.spotify_user_data
    render json: @spotify_user_data
  end

  # GET /spotify_user_data/:id.json
  def show
    render json: @spotify_user_datum
  end

  # GET /spotify_user_data/user/:user_id.json
  def user_data
    @user_data = SpotifyUserDatum.where(user_id: params[:user_id])
    render json: @user_data
  end

  # POST /spotify_user_data.json
  def create
    @spotify_user_datum = current_user.spotify_user_data.new(spotify_user_datum_params)
    if @spotify_user_datum.save
      render json: @spotify_user_datum, status: :created
    else
      render json: @spotify_user_datum.errors, status: :unprocessable_entity
    end
  end

   # POST /spotify_user_data/bulk_create.json
  def bulk_create
    # Borra los datos existentes para el user_id
    current_user.spotify_user_data.destroy_all

    # Crea nuevos datos
    @spotify_user_data = bulk_spotify_user_datum_params.map do |datum|
      current_user.spotify_user_data.create(datum)
    end

    if @spotify_user_data.all?(&:valid?)
      render json: @spotify_user_data, status: :created
    else
      render json: @spotify_user_data.map(&:errors), status: :unprocessable_entity
    end
  end

  # PATCH/PUT /spotify_user_data/:id.json
  def update
    if @spotify_user_datum.update(spotify_user_datum_params)
      render json: @spotify_user_datum
    else
      render json: @spotify_user_datum.errors, status: :unprocessable_entity
    end
  end

  # DELETE /spotify_user_data/:id.json
  def destroy
    @spotify_user_datum.destroy
    head :no_content
  end

  # DELETE /spotify_user_data.json
  def destroy_all
    current_user.spotify_user_data.destroy_all
    head :no_content
  end

  private

  def bulk_spotify_user_datum_params
    params.require(:_json).map do |param|
      param.permit(:artist_name, :image, :preview_url, :track_name, :track_id)
    end
  end

  def set_spotify_user_datum
    @spotify_user_datum = current_user.spotify_user_data.find(params[:id])
  end

  def spotify_user_datum_params
    params.require(:spotify_user_datum).permit(:artist_name, :image, :preview_url, :track_name, :track_id)
  end
end
