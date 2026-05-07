class BlackCoffeeVenueReviewFinalizer
  Result = Struct.new(:total_places, :approved_count, :rejected_count, keyword_init: true)

  def self.call(batch:, reviewer:, rejections:)
    new(batch: batch, reviewer: reviewer, rejections: rejections).call
  end

  def initialize(batch:, reviewer:, rejections:)
    @batch = batch
    @reviewer = reviewer
    @raw_rejections = rejections
  end

  def call
    now = Time.current
    reviewer_id = reviewer&.id
    normalized_rejections = normalize_rejections
    result = nil

    BlackCoffeeReviewBatch.transaction do
      batch.lock!
      raise ArgumentError, 'Este lote ya fue revisado.' if batch.completed?

      items = batch.review_items.includes(:venue).to_a
      items_by_venue_id = items.index_by(&:venue_id)
      venue_ids = items_by_venue_id.keys
      selected_rejections = normalized_rejections.slice(*venue_ids)
      approved_ids = venue_ids - selected_rejections.keys

      selected_rejections.each do |venue_id, rejection|
        update_rejected_venue!(venue_id, rejection, now, reviewer_id)
        update_rejected_item!(items_by_venue_id.fetch(venue_id), rejection, now)
      end

      approve_venues!(approved_ids, now, reviewer_id)
      approve_items!(batch.id, approved_ids, now)

      batch.update!(
        status: 'completed',
        total_places: venue_ids.size,
        approved_count: approved_ids.size,
        rejected_count: selected_rejections.size,
        reviewed_at: now,
        reviewed_by_id: reviewer_id
      )

      result = Result.new(
        total_places: venue_ids.size,
        approved_count: approved_ids.size,
        rejected_count: selected_rejections.size
      )
    end

    result
  end

  private

  attr_reader :batch, :reviewer, :raw_rejections

  def normalize_rejections
    return {} if raw_rejections.blank?

    raw_hash = raw_rejections.respond_to?(:to_unsafe_h) ? raw_rejections.to_unsafe_h : raw_rejections.to_h
    raw_hash.each_with_object({}) do |(venue_id, payload), memo|
      payload_hash = payload.respond_to?(:to_h) ? payload.to_h.with_indifferent_access : {}
      reason = payload_hash[:reason].to_s.strip
      next if reason.blank?

      unless Venue::REJECTION_REASON_CODES.include?(reason)
        raise ArgumentError, "Motivo de rechazo no valido para #{venue_id}: #{reason}"
      end

      memo[venue_id.to_s] = {
        reason: reason,
        note: payload_hash[:note].to_s.strip.presence
      }
    end
  end

  def update_rejected_venue!(venue_id, rejection, now, reviewer_id)
    Venue.where(id: venue_id).update_all(
      review_status: Venue::REVIEW_STATUS_REJECTED,
      review_rejection_reason: rejection.fetch(:reason),
      review_rejection_note: rejection[:note],
      reviewed_at: now,
      reviewed_by_id: reviewer_id,
      updated_at: now
    )
  end

  def update_rejected_item!(item, rejection, now)
    item.update_columns(
      review_status: Venue::REVIEW_STATUS_REJECTED,
      review_rejection_reason: rejection.fetch(:reason),
      review_rejection_note: rejection[:note],
      reviewed_at: now,
      updated_at: now
    )
  end

  def approve_venues!(venue_ids, now, reviewer_id)
    return if venue_ids.empty?

    Venue.where(id: venue_ids).update_all(
      review_status: Venue::REVIEW_STATUS_APPROVED,
      review_rejection_reason: nil,
      review_rejection_note: nil,
      reviewed_at: now,
      reviewed_by_id: reviewer_id,
      updated_at: now
    )
  end

  def approve_items!(batch_id, venue_ids, now)
    return if venue_ids.empty?

    BlackCoffeeReviewBatchItem.where(black_coffee_review_batch_id: batch_id, venue_id: venue_ids).update_all(
      review_status: Venue::REVIEW_STATUS_APPROVED,
      review_rejection_reason: nil,
      review_rejection_note: nil,
      reviewed_at: now,
      updated_at: now
    )
  end
end
