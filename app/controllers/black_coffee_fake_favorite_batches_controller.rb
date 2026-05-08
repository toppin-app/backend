class BlackCoffeeFakeFavoriteBatchesController < ApplicationController
  before_action :check_admin
  before_action :hide_content_header, only: [:index, :show]
  before_action :set_batch, only: [:show, :status, :advance, :retry]

  def index
    @title = 'Favoritos fake · Black Coffee'
    @fake_users_count = User.fake_users.active_accounts.count
    @fake_favorites_count = UserFavorite.where(user_id: User.fake_users.active_accounts.select(:id)).count
    @public_venues_count = Venue.public_catalog_scope.count
    @active_batch = BlackCoffeeFakeFavoriteBatch.active.recent_first.first
    @latest_batches = BlackCoffeeFakeFavoriteBatch.recent_first.limit(12)
    @matrix_preview = BlackCoffeeVenueCombinationMatrix.build(scope: Venue.public_catalog_scope)
  end

  def create
    existing_batch = BlackCoffeeFakeFavoriteBatch.active.recent_first.first
    if existing_batch.present?
      redirect_to black_coffee_fake_favorite_batch_path(existing_batch), notice: 'Ya hay una regeneracion de favoritos fake en curso. Puedes seguirla desde aqui.'
      return
    end

    batch = BlackCoffeeFakeFavoritesRunner.start!
    redirect_to black_coffee_fake_favorite_batch_path(batch), notice: "Regeneracion preparada para #{batch.total_users_count} usuarios fake."
  rescue StandardError => e
    redirect_back fallback_location: black_coffee_fake_favorite_batches_path, alert: "No se pudo preparar la regeneracion: #{e.message}"
  end

  def show
    @title = "Favoritos fake ##{@batch.id}"
    @progress_payload = @batch.as_progress_json
  end

  def status
    render json: @batch.as_progress_json
  end

  def advance
    BlackCoffeeFakeFavoritesRunner.advance!(batch: @batch)
    render json: @batch.reload.as_progress_json
  rescue StandardError => e
    render json: @batch.reload.as_progress_json.merge(errorMessage: e.message), status: :unprocessable_entity
  end

  def retry
    BlackCoffeeFakeFavoritesRunner.retry_failed!(batch: @batch)
    redirect_to black_coffee_fake_favorite_batch_path(@batch), notice: 'Se reiniciara la regeneracion completa de favoritos fake desde cero.'
  rescue StandardError => e
    redirect_to black_coffee_fake_favorite_batch_path(@batch), alert: "No se pudo reintentar la regeneracion: #{e.message}"
  end

  private

  def set_batch
    @batch = BlackCoffeeFakeFavoriteBatch.find(params[:id])
  end
end
