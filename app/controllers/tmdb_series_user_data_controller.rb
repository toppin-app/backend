class TmdbUserSeriesDataController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tmdb_user_series_datum, only: [:show, :update, :destroy]

  # GET /tmdb_user_series_data.json
  def index
    @tmdb_user_series_data = current_user.tmdb_user_series_data
    render json: @tmdb_user_series_data
  end

  # GET /tmdb_user_series_data/:id.json
  def show
    render json: @tmdb_user_series_datum
  end

  # GET /tmdb_user_series_data/user/:user_id.json
  def user_data
    @user_series_data = TmdbUserSeriesDatum.where(user_id: params[:user_id])
    render json: @user_series_data
  end

  # POST /tmdb_user_series_data.json
  def create
    @tmdb_user_series_datum = current_user.tmdb_user_series_data.new(tmdb_user_series_datum_params)
    if @tmdb_user_series_datum.save
      render json: @tmdb_user_series_datum, status: :created
    else
      render json: @tmdb_user_series_datum.errors, status: :unprocessable_entity
    end
  end

  # POST /tmdb_user_series_data/bulk_create.json
  def bulk_create
    current_user.tmdb_user_series_data.destroy_all
    @tmdb_user_series_data = bulk_tmdb_user_series_datum_params.map do |datum|
      current_user.tmdb_user_series_data.create(datum)
    end

    if @tmdb_user_series_data.all?(&:valid?)
      render json: @tmdb_user_series_data, status: :created
    else
      render json: @tmdb_user_series_data.map(&:errors), status: :unprocessable_entity
    end
  end

  # PATCH/PUT /tmdb_user_series_data/:id.json
  def update
    if @tmdb_user_series_datum.update(tmdb_user_series_datum_params)
      render json: @tmdb_user_series_datum
    else
      render json: @tmdb_user_series_datum.errors, status: :unprocessable_entity
    end
  end

  # DELETE /tmdb_user_series_data/:id.json
  def destroy
    @tmdb_user_series_datum.destroy
    head :no_content
  end

  # DELETE /tmdb_user_series_data.json
  def destroy_all
    current_user.tmdb_user_series_data.destroy_all
    head :no_content
  end

  private

  def bulk_tmdb_user_series_datum_params
    params.require(:_json).map do |param|
      param.permit(:title, :poster_path, :overview, :tmdb_id, :release_date)
    end
  end

  def set_tmdb_user_series_datum
    @tmdb_user_series_datum = current_user.tmdb_user_series_data.find(params[:id])
  end

  def tmdb_user_series_datum_params
    params.require(:tmdb_user_series_datum).permit(:title, :poster_path,:tmdb_id, :release_date)
  end
end