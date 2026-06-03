class BlackCoffeeImageInternalizationRunner
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100
  INSERT_BATCH_SIZE = 1_000

  def self.create_batch!(created_by: nil)
    new(created_by: created_by).create_batch!
  end

  def self.advance!(batch:, limit: DEFAULT_LIMIT)
    new(batch: batch, limit: limit).advance!
  end

  def initialize(batch: nil, created_by: nil, limit: DEFAULT_LIMIT, downloader: nil)
    @batch = batch
    @created_by = created_by
    @limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    @downloader = downloader || BlackCoffeeImageDownloader.new
  end

  def create_batch!
    batch = nil

    BlackCoffeeImageInternalizationBatch.transaction do
      candidate_scope = VenueImage
                        .includes(:venue)
                        .where.not(url: [nil, ''])

      batch = BlackCoffeeImageInternalizationBatch.create!(
        status: 'pending',
        total_venues: candidate_scope.select(:venue_id).distinct.count,
        total_images: candidate_scope.count,
        created_by_id: created_by&.id,
        report_payload: {}
      )

      rows = []
      candidate_scope.find_each do |image|
        rows << item_row(batch: batch, image: image)
        flush_rows!(rows)
      end
      flush_rows!(rows, force: true)
      refresh_counts!(batch)
    end

    batch
  end

  def advance!
    raise ArgumentError, 'No hay lote de internalizacion de imagenes.' unless batch
    return refresh_counts!(batch) if batch.finished?

    batch.update!(status: 'running', started_at: batch.started_at || Time.current)
    items = batch.items.pending.includes(:venue_image).ordered.limit(limit).to_a

    items.each do |item|
      item_result = convert_item(item)
      apply_item_result!(item, item_result)
    end

    refresh_counts!(batch)
  rescue StandardError => e
    batch&.update_columns(status: 'failed', error_message: e.message, updated_at: Time.current)
    raise
  end

  private

  attr_reader :batch, :created_by, :limit, :downloader

  def item_row(batch:, image:)
    now = Time.current
    {
      black_coffee_image_internalization_batch_id: batch.id,
      venue_id: image.venue_id,
      venue_image_id: image.id,
      venue_name: image.venue&.name,
      source_url: image.url,
      status: 'pending',
      created_at: now,
      updated_at: now
    }
  end

  def convert_item(item)
    image = item.venue_image
    return missing_image_result(item) unless image

    BlackCoffeeVenueImageLinkConverter.convert_image!(image: image, downloader: downloader)
  end

  def missing_image_result(item)
    BlackCoffeeVenueImageLinkConverter::ItemResult.new(
      venue_image_id: item.venue_image_id,
      status: 'failed',
      source_url: item.source_url,
      error_type: 'missing_image',
      error_message: 'La imagen ya no existe en la base de datos.'
    )
  end

  def apply_item_result!(item, result)
    item.update_columns(
      status: result.status,
      source_url: result.source_url.presence || item.source_url,
      content_type: result.content_type,
      file_size: result.file_size,
      http_status: result.http_status,
      error_type: result.error_type,
      error_message: result.error_message,
      processed_at: Time.current,
      updated_at: Time.current
    )
  end

  def refresh_counts!(internalization_batch)
    pending_venue_ids = internalization_batch.items.pending.distinct.pluck(:venue_id)
    total_items = internalization_batch.items.count
    processed_items = internalization_batch.items.processed.count
    converted_items = internalization_batch.items.converted.count
    converted_venues = internalization_batch.items.converted.select(:venue_id).distinct.count
    failed_items = internalization_batch.items.failed.count
    failed_venues = internalization_batch.items.failed.select(:venue_id).distinct.count
    skipped_items = internalization_batch.items.skipped.count
    status =
      if internalization_batch.cancelled?
        'cancelled'
      elsif internalization_batch.failed?
        'failed'
      elsif internalization_batch.items.pending.exists?
        processed_items.positive? ? 'running' : 'pending'
      else
        'completed'
      end

    internalization_batch.update_columns(
      status: status,
      processed_venues: [internalization_batch.total_venues.to_i - pending_venue_ids.size, 0].max,
      total_images: total_items,
      processed_images: processed_items,
      converted_images_count: converted_items,
      converted_venues_count: converted_venues,
      failed_images_count: failed_items,
      failed_venues_count: failed_venues,
      skipped_images_count: skipped_items,
      completed_at: status == 'completed' ? (internalization_batch.completed_at || Time.current) : internalization_batch.completed_at,
      report_payload: report_payload_for(internalization_batch),
      updated_at: Time.current
    )
    internalization_batch.reload
  end

  def report_payload_for(internalization_batch)
    failed_scope = internalization_batch.items.failed
    skipped_scope = internalization_batch.items.skipped
    {
      error_breakdown: failed_scope.group(:error_type).count,
      skipped_breakdown: skipped_scope.group(:error_type).count,
      sample_failures: failed_scope.ordered.limit(25).map do |item|
        {
          venue_id: item.venue_id,
          venue_name: item.venue_name,
          venue_image_id: item.venue_image_id,
          source_url: item.source_url,
          error_type: item.error_type,
          http_status: item.http_status,
          error_message: item.error_message
        }
      end
    }
  end

  def flush_rows!(rows, force: false)
    return if rows.empty?
    return if !force && rows.size < INSERT_BATCH_SIZE

    BlackCoffeeImageInternalizationItem.insert_all!(rows)
    rows.clear
  end
end
