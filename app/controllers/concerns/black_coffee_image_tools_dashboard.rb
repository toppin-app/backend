module BlackCoffeeImageToolsDashboard
  extend ActiveSupport::Concern

  private

  def prepare_black_coffee_image_tools_dashboard
    @pending_venues_count = Venue.where(review_status: Venue::REVIEW_STATUS_PENDING).count
    @linked_images_count = VenueImage.where.not(url: [nil, '']).count
    @linked_venues_count = VenueImage.where.not(url: [nil, '']).select(:venue_id).distinct.count
    @recent_image_processes = recent_black_coffee_image_processes
  end

  def recent_black_coffee_image_processes
    (black_coffee_image_audit_processes + black_coffee_image_internalization_processes)
      .sort_by { |process| process[:created_at] || Time.zone.at(0) }
      .reverse
      .first(50)
  end

  def black_coffee_image_audit_processes
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

  def black_coffee_image_internalization_processes
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
