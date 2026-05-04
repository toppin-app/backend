class BlackCoffeeVenueGoogleSyncBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze
  SELECTION_MODES = %w[selected_ids connected_scope].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :selection_mode, inclusion: { in: SELECTION_MODES }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def venue_ids
    normalized_id_array(venue_ids_payload)
  end

  def pending_venue_ids
    normalized_id_array(pending_venue_ids_payload)
  end

  def failed_venue_ids
    normalized_id_array(failed_venue_ids_payload)
  end

  def active?
    status.in?(%w[pending running])
  end

  def finished?
    status.in?(%w[completed failed cancelled])
  end

  def retryable?
    status == 'failed' && failed_venue_ids.any?
  end

  def connected_scope?
    selection_mode == 'connected_scope'
  end

  def selected_ids?
    selection_mode == 'selected_ids'
  end

  def completion_percentage
    total = total_venues_count.to_i
    return 0 if total.zero?

    ((processed_venues_count.to_f / total) * 100).round
  end

  def as_progress_json
    {
      id: id,
      status: status,
      selectionMode: selection_mode,
      active: active?,
      finished: finished?,
      retryable: retryable?,
      totalVenues: total_venues_count.to_i,
      pendingVenues: pending_venues_count.to_i,
      processedVenues: processed_venues_count.to_i,
      syncedVenues: synced_venues_count.to_i,
      skippedVenues: skipped_venues_count.to_i,
      failedVenues: failed_venues_count.to_i,
      requestsCount: requests_count.to_i,
      completionPercentage: completion_percentage,
      currentVenueId: current_venue_id,
      currentVenueName: current_venue_name,
      lastProcessedVenueId: last_processed_venue_id,
      startedAt: started_at,
      lastAdvancedAt: last_advanced_at,
      finishedAt: finished_at,
      errorMessage: error_message
    }
  end

  private

  def normalized_id_array(value)
    Array(value).map { |entry| entry.to_s.strip }.reject(&:blank?).uniq
  end
end
