class BlackCoffeeImageInternalizationsController < ApplicationController
  before_action :check_admin
  before_action :hide_content_header
  before_action :set_batch, only: [:show, :advance, :cancel]

  def index
    @title = 'Internalizacion de imagenes Black Coffee'
    @linked_images_count = VenueImage.where.not(url: [nil, '']).count
    @linked_venues_count = VenueImage.where.not(url: [nil, '']).select(:venue_id).distinct.count
    @recent_batches = BlackCoffeeImageInternalizationBatch.recent_first.limit(20)
  end

  def create
    batch = BlackCoffeeImageInternalizationRunner.create_batch!(created_by: current_user)
    redirect_to black_coffee_image_internalization_path(batch), notice: "Lote creado con #{batch.total_images} imagenes enlazadas en #{batch.total_venues} locales."
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_internalizations_path, alert: "No se pudo crear el lote: #{e.message}"
  end

  def show
    @title = "Internalizacion de imagenes ##{@batch.id}"
    @auto_processing = auto_processing?
    @process_limit = process_limit
    @failed_items = @batch.items.failed.includes(:venue).ordered.limit(200)
    @skipped_items = @batch.items.skipped.includes(:venue).ordered.limit(100)
    @converted_items = @batch.items.converted.includes(:venue).ordered.limit(100)
    @error_breakdown = @batch.items.failed.group(:error_type).count
    @skipped_breakdown = @batch.items.skipped.group(:error_type).count
  end

  def advance
    BlackCoffeeImageInternalizationRunner.advance!(batch: @batch, limit: process_limit)
    redirect_to advance_redirect_path, notice: 'Bloque de imagenes internalizado.'
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_internalization_path(@batch), alert: "No se pudo procesar el bloque: #{e.message}"
  end

  def cancel
    if @batch.finished?
      redirect_to black_coffee_image_internalization_path(@batch), alert: 'Este lote ya esta finalizado.'
      return
    end

    @batch.update!(status: 'cancelled', completed_at: Time.current)
    redirect_to black_coffee_image_internalization_path(@batch), notice: 'Procesamiento automatico cancelado. Los items pendientes quedan sin tocar.'
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to black_coffee_image_internalization_path(@batch), alert: "No se pudo cancelar el lote: #{e.message}"
  end

  private

  def set_batch
    @batch = BlackCoffeeImageInternalizationBatch.find(params[:id])
  end

  def process_limit
    raw_limit = params[:limit].presence || BlackCoffeeImageInternalizationRunner::DEFAULT_LIMIT
    [[raw_limit.to_i, 1].max, BlackCoffeeImageInternalizationRunner::MAX_LIMIT].min
  end

  def auto_processing?
    ActiveModel::Type::Boolean.new.cast(params[:auto])
  end

  def advance_redirect_path
    @batch.reload
    return black_coffee_image_internalization_path(@batch) unless auto_processing?
    return black_coffee_image_internalization_path(@batch) if @batch.finished? || !@batch.pending_items?

    black_coffee_image_internalization_path(@batch, auto: 1, limit: process_limit)
  end
end
