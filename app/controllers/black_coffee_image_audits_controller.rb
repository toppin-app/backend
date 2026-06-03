class BlackCoffeeImageAuditsController < ApplicationController
  before_action :check_admin
  before_action :hide_content_header
  before_action :set_batch, only: [:show, :advance, :reject_failed]

  def index
    @title = 'Auditoria de imagenes Black Coffee'
    @pending_venues_count = Venue.where(review_status: Venue::REVIEW_STATUS_PENDING).count
    @recent_image_processes = recent_image_processes
  end

  def create
    batch = BlackCoffeePendingImageAuditRunner.create_batch!(base_url: request.base_url)
    redirect_to black_coffee_image_audit_path(batch), notice: "Auditoria creada con #{batch.total_venues} locales pendientes y #{batch.total_images} comprobaciones de imagen."
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_audits_path, alert: "No se pudo crear la auditoria: #{e.message}"
  end

  def show
    @title = "Auditoria de imagenes ##{@batch.id}"
    @failed_items = @batch.items.failed.includes(:venue).ordered.limit(200)
    @error_breakdown = @batch.items.failed.group(:error_type).count
  end

  def advance
    BlackCoffeePendingImageAuditRunner.advance!(batch: @batch, limit: process_limit)
    redirect_to black_coffee_image_audit_path(@batch), notice: 'Bloque de imagenes procesado.'
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_image_audit_path(@batch), alert: "No se pudo procesar el bloque: #{e.message}"
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
    [[params[:limit].to_i, 1].max, BlackCoffeePendingImageAuditRunner::MAX_LIMIT].min
  end

  def recent_image_processes
    (audit_processes + internalization_processes)
      .sort_by { |process| process[:created_at] || Time.zone.at(0) }
      .reverse
      .first(50)
  end

  def audit_processes
    BlackCoffeeImageAuditBatch.recent_first.limit(50).map do |batch|
      {
        type: 'Auditoria',
        id: batch.id,
        status_label: batch.status_label,
        badge_class: batch.status_badge_class,
        progress_percentage: batch.progress_percentage,
        processed: batch.checked_images,
        total: batch.total_images,
        unit: 'checks',
        failed_venues_count: batch.failed_venues_count,
        failed_images_count: batch.failed_images_count,
        rejected_venues_count: batch.rejected_venues_count,
        created_at: batch.created_at,
        action_label: 'Ver reporte',
        path: black_coffee_image_audit_path(batch)
      }
    end
  end

  def internalization_processes
    return [] unless ActiveRecord::Base.connection.data_source_exists?('black_coffee_image_internalization_batches')

    BlackCoffeeImageInternalizationBatch.recent_first.limit(50).map do |batch|
      {
        type: 'Internalizacion',
        id: batch.id,
        status_label: batch.status_label,
        badge_class: batch.status_badge_class,
        progress_percentage: batch.progress_percentage,
        processed: batch.processed_images,
        total: batch.total_images,
        unit: 'imagenes',
        failed_venues_count: batch.failed_venues_count,
        failed_images_count: batch.failed_images_count,
        rejected_venues_count: nil,
        created_at: batch.created_at,
        action_label: 'Ver lote',
        path: black_coffee_image_internalization_path(batch)
      }
    end
  end
end
