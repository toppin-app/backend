class BlackCoffeeConcertCoverRepairRunner
  DEFAULT_LIMIT = 10
  MAX_LIMIT = 25
  MAX_BLOCK_RUNTIME_SECONDS = 55
  CANCELLATION_CHECK_INTERVAL = 1
  INSERT_BATCH_SIZE = 500
  REJECTION_REASON = 'bad_photos'.freeze

  def self.create_batch!(created_by:, review_status_filter: 'approved', external_search_enabled: false)
    new(
      created_by: created_by,
      review_status_filter: review_status_filter,
      external_search_enabled: external_search_enabled
    ).create_batch!
  end

  def self.advance!(batch:, limit: DEFAULT_LIMIT, resolver: nil, attacher: BlackCoffeeConcertCoverAttachment)
    new(batch: batch, limit: limit, resolver: resolver, attacher: attacher).advance!
  end

  def initialize(
    batch: nil,
    created_by: nil,
    review_status_filter: 'approved',
    external_search_enabled: false,
    limit: DEFAULT_LIMIT,
    resolver: nil,
    attacher: BlackCoffeeConcertCoverAttachment
  )
    @batch = batch
    @created_by = created_by
    @review_status_filter = review_status_filter.to_s
    @external_search_enabled = ActiveModel::Type::Boolean.new.cast(external_search_enabled)
    @limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    @resolver = resolver
    @attacher = attacher
  end

  def create_batch!
    validate_review_status_filter!
    batch = nil

    BlackCoffeeConcertCoverRepairBatch.transaction do
      scope = candidate_scope
      batch = BlackCoffeeConcertCoverRepairBatch.create!(
        status: 'pending',
        review_status_filter: review_status_filter,
        external_search_enabled: external_search_enabled,
        total_venues: scope.count,
        created_by: created_by,
        report_payload: {}
      )

      rows = []
      scope.find_each do |venue|
        rows << {
          black_coffee_concert_cover_repair_batch_id: batch.id,
          venue_id: venue.id,
          venue_name: venue.name,
          status: 'pending',
          original_review_status: venue.review_status,
          source_page_url: venue.external_source_url,
          created_at: Time.current,
          updated_at: Time.current
        }
        flush_rows!(rows)
      end
      flush_rows!(rows, force: true)
      refresh_counts!(batch)
    end

    batch
  end

  def advance!
    raise ArgumentError, 'No hay lote de recuperacion de portadas.' unless batch
    return refresh_counts!(batch) if batch.finished?

    batch.update!(status: 'running', started_at: batch.started_at || Time.current)
    items = batch.items.pending.includes(venue: :venue_images).ordered.limit(limit).to_a
    started_at = monotonic_time
    processed = 0
    source_before = cover_resolver.source_total_requests_count
    search_before = cover_resolver.search_requests_count
    image_before = cover_resolver.image_download_requests_count

    items.each do |item|
      break if time_budget_exhausted?(started_at, processed)
      break if cancellation_requested?(processed)

      process_item_safely!(item)
      processed += 1
    end

    persist_request_deltas!(source_before: source_before, search_before: search_before, image_before: image_before)
    refresh_counts!(batch)
  rescue StandardError => e
    if defined?(source_before) && defined?(search_before) && defined?(image_before)
      persist_request_deltas!(source_before: source_before, search_before: search_before, image_before: image_before)
    end
    batch&.update_columns(
      status: 'failed',
      error_message: "#{e.class} - #{e.message}",
      last_worker_heartbeat_at: Time.current,
      updated_at: Time.current
    )
    raise
  end

  private

  attr_reader :batch, :created_by, :review_status_filter, :external_search_enabled, :limit, :attacher

  def candidate_scope
    scope = Venue.where(category: 'concierto')
    scope = scope.where(review_status: review_statuses_for_filter)
    scope = scope.where.not(id: VenueImage.where.not(image: [nil, '']).select(:venue_id))
    scope = scope.where(event_status: Venue::EVENT_STATUS_UPCOMING) if Venue.column_names.include?('event_status')
    scope.order(:id)
  end

  def review_statuses_for_filter
    case review_status_filter
    when 'approved'
      [Venue::REVIEW_STATUS_APPROVED]
    when 'pending'
      [Venue::REVIEW_STATUS_PENDING]
    when 'active'
      [Venue::REVIEW_STATUS_APPROVED, Venue::REVIEW_STATUS_PENDING]
    else
      []
    end
  end

  def validate_review_status_filter!
    return if BlackCoffeeConcertCoverRepairBatch::REVIEW_STATUS_FILTERS.include?(review_status_filter)

    raise ArgumentError, "Filtro de revision no valido: #{review_status_filter}"
  end

  def process_item_safely!(item)
    venue = item.venue
    return skip_item!(item, 'missing_venue', 'El concierto ya no existe.') unless venue
    return skip_item!(item, 'cover_already_present', 'El concierto ya tiene una portada interna.') if uploaded_cover?(venue)
    return skip_item!(item, 'review_status_changed', 'El estado de revision cambio desde que se creo el lote.') unless review_statuses_for_filter.include?(venue.review_status)

    result = cover_resolver.resolve_for_venue(venue)
    if result.recovered?
      attach_recovered_cover!(item, venue, result)
    elsif result.missing?
      reject_without_cover!(item, venue, result)
    else
      fail_unresolved_item!(item, result)
    end
  rescue StandardError => e
    item.update_columns(
      status: 'failed',
      error_type: 'unexpected_item_error',
      error_message: "#{e.class} - #{e.message}",
      processed_at: Time.current,
      updated_at: Time.current
    )
  end

  def attach_recovered_cover!(item, venue, result)
    attacher.attach!(
      venue: venue,
      download: result.download,
      resolution_source: result.resolution_source,
      source_url: result.image_url,
      provenance: cover_provenance(result)
    )
    status = result.resolution_source == 'brave_search' ? 'recovered_search' : 'recovered_source'
    item.update_columns(
      status: status,
      resolution_source: result.resolution_source,
      selected_image_url: result.image_url,
      result_page_url: result.page_url,
      confidence: result.confidence,
      evidence: result.evidence,
      error_type: nil,
      error_message: nil,
      processed_at: Time.current,
      updated_at: Time.current
    )
  end

  def reject_without_cover!(item, venue, result)
    Venue.transaction do
      venue.update!(
        review_status: Venue::REVIEW_STATUS_REJECTED,
        review_rejection_reason: REJECTION_REASON,
        review_rejection_note: rejection_note(result),
        reviewed_at: Time.current,
        reviewed_by_id: batch.created_by_id,
        visible: false,
        featured: false
      )
      item.update!(
        status: 'rejected',
        error_type: result.error_type.presence || 'no_cover_found',
        error_message: result.error_message.presence || 'No se encontro una portada verificable.',
        evidence: result.evidence,
        processed_at: Time.current
      )
    end
  end

  def fail_unresolved_item!(item, result)
    item.update_columns(
      status: 'failed',
      error_type: result.error_type.presence || 'cover_resolution_unavailable',
      error_message: result.error_message.presence || 'No se pudieron completar todas las vias de recuperacion; el concierto no fue rechazado.',
      evidence: result.evidence,
      processed_at: Time.current,
      updated_at: Time.current
    )
  end

  def cover_provenance(result)
    {
      source_page_url: result.page_url,
      original_image_url: result.image_url,
      resolution_source: result.resolution_source,
      confidence: result.confidence,
      evidence: result.evidence
    }.compact
  end

  def rejection_note(result)
    details = result.error_message.to_s.squish.first(700)
    "Descartado automaticamente por la herramienta de portadas: no se pudo recuperar una imagen binaria verificable desde la fuente original ni mediante la busqueda estricta. #{details}".squish
  end

  def uploaded_cover?(venue)
    venue.venue_images.any?(&:uploaded_image?)
  end

  def skip_item!(item, error_type, message)
    item.update_columns(
      status: 'skipped',
      error_type: error_type,
      error_message: message,
      processed_at: Time.current,
      updated_at: Time.current
    )
  end

  def cover_resolver
    @resolver ||= BlackCoffeeConcertCoverResolver.new(
      external_search_enabled: batch.external_search_enabled
    )
  end

  def time_budget_exhausted?(started_at, processed)
    processed.positive? && (monotonic_time - started_at) >= MAX_BLOCK_RUNTIME_SECONDS
  end

  def cancellation_requested?(processed)
    return false unless processed.positive?
    return false unless (processed % CANCELLATION_CHECK_INTERVAL).zero?

    batch.reload.cancelled?
  end

  def persist_request_deltas!(source_before:, search_before:, image_before:)
    source_delta = [cover_resolver.source_total_requests_count - source_before.to_i, 0].max
    search_delta = [cover_resolver.search_requests_count - search_before.to_i, 0].max
    image_delta = [cover_resolver.image_download_requests_count - image_before.to_i, 0].max
    return if source_delta.zero? && search_delta.zero? && image_delta.zero?

    batch.with_lock do
      batch.reload
      batch.update_columns(
        source_requests_count: batch.source_requests_count.to_i + source_delta,
        search_requests_count: batch.search_requests_count.to_i + search_delta,
        image_requests_count: batch.image_requests_count.to_i + image_delta,
        updated_at: Time.current
      )
    end
  end

  def refresh_counts!(repair_batch)
    repair_batch.reload
    counts = repair_batch.items.group(:status).count
    processed = repair_batch.items.processed.count
    status =
      if repair_batch.cancelled?
        'cancelled'
      elsif repair_batch.failed?
        'failed'
      elsif repair_batch.items.pending.exists?
        processed.positive? ? 'running' : 'pending'
      else
        'completed'
      end

    repair_batch.update_columns(
      status: status,
      total_venues: repair_batch.items.count,
      processed_venues: processed,
      source_recovered_count: counts['recovered_source'].to_i,
      search_recovered_count: counts['recovered_search'].to_i,
      rejected_count: counts['rejected'].to_i,
      failed_count: counts['failed'].to_i,
      skipped_count: counts['skipped'].to_i,
      completed_at: status == 'completed' ? (repair_batch.completed_at || Time.current) : repair_batch.completed_at,
      report_payload: report_payload_for(repair_batch),
      last_worker_heartbeat_at: Time.current,
      updated_at: Time.current
    )
    repair_batch.reload
  end

  def report_payload_for(repair_batch)
    {
      outcome_breakdown: repair_batch.items.group(:status).count,
      error_breakdown: repair_batch.items.where(status: %w[rejected failed skipped]).group(:error_type).count,
      sample_unresolved: repair_batch.items.where(status: %w[rejected failed]).ordered.limit(25).map do |item|
        {
          venue_id: item.venue_id,
          venue_name: item.venue_name,
          status: item.status,
          error_type: item.error_type,
          error_message: item.error_message
        }
      end
    }
  end

  def flush_rows!(rows, force: false)
    return if rows.empty?
    return if !force && rows.size < INSERT_BATCH_SIZE

    BlackCoffeeConcertCoverRepairItem.insert_all!(rows)
    rows.clear
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
