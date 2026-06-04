class BlackCoffeeImageInternalizationsController < ApplicationController
  include BlackCoffeeImageToolsDashboard

  before_action :check_admin
  before_action :hide_content_header
  before_action :set_batch, only: [:show, :start_background, :advance, :cancel]

  def index
    @title = 'Herramientas de imagenes Black Coffee'
    prepare_black_coffee_image_tools_dashboard
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
    @server_processing = @batch.server_processing?
    @failed_items = @batch.items.failed.includes(:venue).ordered.limit(200)
    @skipped_items = @batch.items.skipped.includes(:venue).ordered.limit(100)
    @converted_items = @batch.items.converted.includes(:venue).ordered.limit(100)
    @error_breakdown = @batch.items.failed.group(:error_type).count
    @skipped_breakdown = @batch.items.skipped.group(:error_type).count
  end

  def start_background
    if @batch.finished?
      redirect_to black_coffee_image_internalization_path(@batch), alert: 'Este lote ya esta finalizado.'
      return
    end

    token = SecureRandom.hex(16)
    @batch.update!(
      status: 'running',
      processing_mode: 'server',
      background_started_at: @batch.background_started_at || Time.current,
      background_requested_limit: process_limit,
      last_worker_heartbeat_at: Time.current,
      worker_token: token
    )
    BlackCoffeeImageInternalizationJob.perform_later(@batch.id, process_limit, token)
    redirect_to black_coffee_image_internalization_path(@batch),
                notice: "Procesamiento en servidor iniciado con bloques de hasta #{process_limit} imagenes. Puedes cerrar esta pantalla y volver luego."
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_internalization_path(@batch), alert: "No se pudo iniciar el procesamiento en servidor: #{e.message}"
  end

  def advance
    @batch.update_columns(processing_mode: auto_processing? ? 'browser' : 'manual', worker_token: nil, updated_at: Time.current) if @batch.has_attribute?(:processing_mode)
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

    @batch.update!(
      status: 'cancelled',
      completed_at: Time.current,
      worker_token: nil
    )
    redirect_to black_coffee_image_internalization_path(@batch), notice: 'Procesamiento cancelado. Los items pendientes quedan sin tocar.'
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
