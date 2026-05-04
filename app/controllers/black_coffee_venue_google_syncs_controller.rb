class BlackCoffeeVenueGoogleSyncsController < ApplicationController
  before_action :check_admin
  before_action :set_batch, only: [:show, :status, :advance, :retry]

  def index
    @title = 'Sincronizacion Google · Black Coffee'
    @connected_venues_count = Venue.google_connected.count
    @venues_without_google_count = [Venue.count - @connected_venues_count, 0].max
    @active_batch = BlackCoffeeVenueGoogleSyncBatch.active.recent_first.first
    @latest_batches = BlackCoffeeVenueGoogleSyncBatch.recent_first.limit(12)
  end

  def create
    existing_batch = BlackCoffeeVenueGoogleSyncBatch.active.recent_first.first
    if existing_batch.present?
      redirect_to black_coffee_venue_google_sync_path(existing_batch), notice: 'Ya hay una sincronizacion Google en curso. Puedes seguirla desde aqui.'
      return
    end

    if params[:venue_id].present?
      batch = BlackCoffeeVenueGoogleSyncRunner.start_selected!(venue_ids: [params[:venue_id]])
      venue_name = Venue.where(id: params[:venue_id].to_s).pick(:name)
      redirect_to black_coffee_venue_google_sync_path(batch), notice: "Sincronizacion preparada para #{venue_name || 'el local seleccionado'}."
      return
    end

    batch = BlackCoffeeVenueGoogleSyncRunner.start_connected_scope!
    redirect_to black_coffee_venue_google_sync_path(batch), notice: "Sincronizacion masiva preparada para #{batch.total_venues_count} locales conectados a Google."
  rescue StandardError => e
    redirect_back fallback_location: black_coffee_venue_google_syncs_path, alert: "No se pudo preparar la sincronizacion Google: #{e.message}"
  end

  def show
    @title = "Sincronizacion Google ##{@batch.id}"
    @progress_payload = @batch.as_progress_json
  end

  def status
    render json: @batch.as_progress_json
  end

  def advance
    BlackCoffeeVenueGoogleSyncRunner.advance!(batch: @batch)
    render json: @batch.reload.as_progress_json
  rescue StandardError => e
    render json: @batch.reload.as_progress_json.merge(errorMessage: e.message), status: :unprocessable_entity
  end

  def retry
    BlackCoffeeVenueGoogleSyncRunner.retry_failed!(batch: @batch)
    redirect_to black_coffee_venue_google_sync_path(@batch), notice: 'Reintentaremos solo los locales que hayan quedado pendientes o con error.'
  rescue StandardError => e
    redirect_to black_coffee_venue_google_sync_path(@batch), alert: "No se pudo reanudar la sincronizacion Google: #{e.message}"
  end

  private

  def set_batch
    @batch = BlackCoffeeVenueGoogleSyncBatch.find(params[:id])
  end
end
