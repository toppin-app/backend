class BlackCoffeeVenueReviewBatchReverter
  Result = Struct.new(:total_places, :approved_count, :rejected_count, keyword_init: true)

  def self.call(batch:)
    new(batch: batch).call
  end

  def initialize(batch:)
    @batch = batch
  end

  def call
    result = nil

    BlackCoffeeReviewBatch.transaction do
      batch.lock!
      items = batch.review_items.to_a
      venue_ids = items.map(&:venue_id).uniq
      now = Time.current

      Venue.where(id: venue_ids).update_all(
        review_status: Venue::REVIEW_STATUS_PENDING,
        review_rejection_reason: nil,
        review_rejection_note: nil,
        reviewed_at: nil,
        reviewed_by_id: nil,
        updated_at: now
      )

      result = Result.new(
        total_places: venue_ids.size,
        approved_count: items.count(&:approved?),
        rejected_count: items.count(&:rejected?)
      )

      batch.destroy!
    end

    result
  end

  private

  attr_reader :batch
end
