class BlackCoffeeVenueReviewFinalizer
  Result = Struct.new(:total_places, :approved_count, :rejected_count, :corrected_count, keyword_init: true)

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
    normalized_decisions = normalize_decisions
    result = nil

    BlackCoffeeReviewBatch.transaction do
      batch.lock!
      raise ArgumentError, 'Este lote ya fue revisado.' if batch.completed?

      items = batch.review_items.includes(:venue).to_a
      items_by_venue_id = items.index_by(&:venue_id)
      venue_ids = items_by_venue_id.keys
      selected_decisions = normalized_decisions.slice(*venue_ids)
      selected_rejections = selected_decisions.select { |_venue_id, decision| decision[:action] == :reject }
      selected_category_corrections = selected_decisions.select { |_venue_id, decision| decision[:action] == :correct_category }
      approved_ids = venue_ids - selected_rejections.keys
      standard_approved_ids = approved_ids - selected_category_corrections.keys

      selected_rejections.each do |venue_id, rejection|
        update_rejected_venue!(venue_id, rejection, now, reviewer_id)
        update_rejected_item!(items_by_venue_id.fetch(venue_id), rejection, now)
      end

      selected_category_corrections.each do |venue_id, correction|
        item = items_by_venue_id.fetch(venue_id)
        update_category_corrected_venue!(item, correction, now, reviewer_id)
        update_category_corrected_item!(item, correction, now)
      end

      approve_venues!(standard_approved_ids, now, reviewer_id)
      approve_items!(batch.id, standard_approved_ids, now)

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
        rejected_count: selected_rejections.size,
        corrected_count: selected_category_corrections.size
      )
    end

    result
  end

  private

  attr_reader :batch, :reviewer, :raw_rejections

  def normalize_decisions
    return {} if raw_rejections.blank?

    raw_hash = raw_rejections.respond_to?(:to_unsafe_h) ? raw_rejections.to_unsafe_h : raw_rejections.to_h
    raw_hash.each_with_object({}) do |(venue_id, payload), memo|
      payload_hash = payload.respond_to?(:to_h) ? payload.to_h.with_indifferent_access : {}
      reason = payload_hash[:reason].to_s.strip
      next if reason.blank?

      unless Venue::REJECTION_REASON_CODES.include?(reason)
        raise ArgumentError, "Motivo de rechazo no valido para #{venue_id}: #{reason}"
      end

      if reason == 'wrong_category' && ActiveModel::Type::Boolean.new.cast(payload_hash[:correct_category])
        corrected_category = payload_hash[:corrected_category].to_s.strip
        unless Venue::CATEGORIES.include?(corrected_category)
          raise ArgumentError, "Categoria corregida no valida para #{venue_id}: #{corrected_category.presence || 'sin categoria'}"
        end

        memo[venue_id.to_s] = {
          action: :correct_category,
          reason: reason,
          corrected_category: corrected_category,
          note: payload_hash[:note].to_s.strip.presence
        }
        next
      end

      memo[venue_id.to_s] = {
        action: :reject,
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
      category_correction_from: nil,
      category_correction_to: nil,
      venue_subcategory_correction_from_id: nil,
      reviewed_at: now,
      updated_at: now
    )
  end

  def update_category_corrected_venue!(item, correction, now, reviewer_id)
    venue = item.venue
    raise ArgumentError, "Local #{item.venue_id} no existe." unless venue

    corrected_category = correction.fetch(:corrected_category)
    if corrected_category == venue.category
      raise ArgumentError, "Selecciona una categoria distinta para #{venue.name}."
    end

    Venue.where(id: venue.id).update_all(
      category: corrected_category,
      venue_subcategory_id: nil,
      review_status: Venue::REVIEW_STATUS_APPROVED,
      review_rejection_reason: nil,
      review_rejection_note: nil,
      reviewed_at: now,
      reviewed_by_id: reviewer_id,
      updated_at: now
    )
  end

  def update_category_corrected_item!(item, correction, now)
    venue = item.venue

    item.update_columns(
      review_status: Venue::REVIEW_STATUS_APPROVED,
      review_rejection_reason: nil,
      review_rejection_note: correction[:note],
      category_correction_from: venue.category,
      category_correction_to: correction.fetch(:corrected_category),
      venue_subcategory_correction_from_id: venue.venue_subcategory_id,
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
      category_correction_from: nil,
      category_correction_to: nil,
      venue_subcategory_correction_from_id: nil,
      reviewed_at: now,
      updated_at: now
    )
  end
end
