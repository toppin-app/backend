class BlackCoffeeImportPhotoRefreshBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze

  belongs_to :black_coffee_import_run,
             inverse_of: :photo_refresh_batches

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def candidate_ids
    normalized_id_array(candidate_ids_payload)
  end

  def pending_candidate_ids
    normalized_id_array(pending_candidate_ids_payload)
  end

  def refreshed_candidate_ids
    normalized_id_array(refreshed_candidate_ids_payload)
  end

  def skipped_candidate_ids
    normalized_id_array(skipped_candidate_ids_payload)
  end

  def failed_candidate_ids
    normalized_id_array(failed_candidate_ids_payload)
  end

  def active?
    status.in?(%w[pending running])
  end

  def finished?
    status.in?(%w[completed failed cancelled])
  end

  def retryable?
    status == 'failed' && pending_candidate_ids.any?
  end

  def completion_percentage
    total = total_candidates_count.to_i
    return 0 if total.zero?

    ((processed_candidates_count.to_f / total) * 100).round
  end

  def as_progress_json
    {
      id: id,
      status: status,
      active: active?,
      finished: finished?,
      retryable: retryable?,
      totalCandidates: total_candidates_count.to_i,
      pendingCandidates: pending_candidates_count.to_i,
      processedCandidates: processed_candidates_count.to_i,
      refreshedCandidates: refreshed_candidates_count.to_i,
      skippedCandidates: skipped_candidates_count.to_i,
      failedCandidates: failed_candidates_count.to_i,
      requestsCount: requests_count.to_i,
      completionPercentage: completion_percentage,
      currentCandidateId: current_candidate_id,
      currentCandidateName: current_candidate_name,
      startedAt: started_at,
      lastAdvancedAt: last_advanced_at,
      finishedAt: finished_at,
      errorMessage: error_message
    }
  end

  def refresh_counts!
    update!(
      total_candidates_count: candidate_ids.size,
      pending_candidates_count: pending_candidate_ids.size,
      processed_candidates_count: refreshed_candidate_ids.size + skipped_candidate_ids.size + failed_candidate_ids.size,
      refreshed_candidates_count: refreshed_candidate_ids.size,
      skipped_candidates_count: skipped_candidate_ids.size,
      failed_candidates_count: failed_candidate_ids.size
    )
  end

  private

  def normalized_id_array(value)
    Array(value).filter_map do |entry|
      id = entry.to_i
      id.positive? ? id : nil
    end.uniq
  end
end
