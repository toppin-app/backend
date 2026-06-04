class BlackCoffeeImageAuditsController < ApplicationController
  include BlackCoffeeImageToolsDashboard

  before_action :check_admin
  before_action :hide_content_header
  before_action :set_batch, only: [:show, :start_background, :advance, :cancel, :reject_failed]

  def index
    @title = 'Herramientas de imagenes Black Coffee'
    prepare_black_coffee_image_tools_dashboard
  end

  def create
    batch = BlackCoffeePendingImageAuditRunner.create_batch!(
      base_url: request.base_url,
      review_status_filter: review_status_filter
    )
    if start_background_after_create?
      start_background_for(batch)
      redirect_to black_coffee_image_audit_path(batch),
                  notice: "Auditoria creada y arrancada en servidor para #{batch.review_status_filter_label.downcase}: #{batch.total_venues} locales y #{batch.total_images} comprobaciones."
    else
      redirect_to black_coffee_image_audit_path(batch),
                  notice: "Auditoria creada para #{batch.review_status_filter_label.downcase}: #{batch.total_venues} locales y #{batch.total_images} comprobaciones de imagen. Pulsa Procesar en servidor para arrancarla en background."
    end
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_audits_path, alert: "No se pudo crear la auditoria: #{e.message}"
  end

  def show
    @title = "Auditoria de imagenes ##{@batch.id}"
    normalize_prepared_batch_status!
    @process_limit = process_limit
    @server_processing = @batch.server_processing?
    @failed_items = @batch.items.failed.includes(:venue).ordered.limit(200)
    @error_breakdown = @batch.items.failed.group(:error_type).count
  end

  def start_background
    if @batch.finished?
      redirect_to black_coffee_image_audit_path(@batch), alert: 'Esta auditoria ya esta finalizada.'
      return
    end

    token = SecureRandom.hex(16)
    start_background_for(@batch, token: token)
    redirect_to black_coffee_image_audit_path(@batch),
                notice: "Auditoria en servidor iniciada con bloques de hasta #{process_limit} imagenes. Puedes cerrar esta pantalla y volver luego."
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_audit_path(@batch), alert: "No se pudo iniciar la auditoria en servidor: #{e.message}"
  end

  def advance
    @batch.update_columns(processing_mode: 'manual', worker_token: nil, updated_at: Time.current) if @batch.has_attribute?(:processing_mode)
    BlackCoffeePendingImageAuditRunner.advance!(batch: @batch, limit: process_limit)
    redirect_to black_coffee_image_audit_path(@batch), notice: 'Bloque de imagenes procesado.'
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_audit_path(@batch), alert: "No se pudo procesar el bloque: #{e.message}"
  end

  def cancel
    if @batch.finished?
      redirect_to black_coffee_image_audit_path(@batch), alert: 'Esta auditoria ya esta finalizada.'
      return
    end

    @batch.update!(
      status: 'cancelled',
      completed_at: Time.current,
      worker_token: nil
    )
    redirect_to black_coffee_image_audit_path(@batch), notice: 'Auditoria cancelada. Las comprobaciones pendientes quedan sin tocar.'
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to black_coffee_image_audit_path(@batch), alert: "No se pudo cancelar la auditoria: #{e.message}"
  end

  def reject_failed
    rejected_count = BlackCoffeePendingImageAuditRunner.reject_failed!(batch: @batch, reviewer: current_user)
    redirect_to black_coffee_image_audit_path(@batch), notice: "#{rejected_count} locales pendientes fueron marcados como rechazados por problemas de imagen."
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_audit_path(@batch), alert: "No se pudieron marcar rechazos: #{e.message}"
  end

  private

  def set_batch
    @batch = BlackCoffeeImageAuditBatch.find(params[:id])
  end

  def process_limit
    raw_limit = params[:limit].presence || BlackCoffeePendingImageAuditRunner::DEFAULT_LIMIT
    [[raw_limit.to_i, 1].max, BlackCoffeePendingImageAuditRunner::MAX_LIMIT].min
  end

  def review_status_filter
    params[:review_status_filter].presence || Venue::REVIEW_STATUS_PENDING
  end

  def start_background_after_create?
    ActiveModel::Type::Boolean.new.cast(params[:start_background])
  end

  def start_background_for(batch, token: SecureRandom.hex(16))
    batch.update!(
      status: 'running',
      processing_mode: 'server',
      started_at: batch.started_at || Time.current,
      background_started_at: batch.background_started_at || Time.current,
      background_requested_limit: process_limit,
      last_worker_heartbeat_at: Time.current,
      worker_token: token
    )
    BlackCoffeeImageAuditJob.perform_later(batch.id, process_limit, token)
  end

  def normalize_prepared_batch_status!
    return unless @batch.running?
    return if @batch.started_at.present?
    return if @batch.server_processing?

    BlackCoffeePendingImageAuditRunner.refresh!(batch: @batch)
  end
end
