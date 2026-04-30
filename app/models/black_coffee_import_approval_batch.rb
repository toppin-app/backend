class BlackCoffeeImportApprovalBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze
  SELECTION_MODES = %w[selected_ids pending_scope].freeze

  belongs_to :black_coffee_import_run,
             inverse_of: :approval_batches

  validates :status, inclusion: { in: STATUSES }
  validates :selection_mode, inclusion: { in: SELECTION_MODES }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def candidate_ids
    normalized_id_array(candidate_ids_payload)
  end

  def pending_candidate_ids
    normalized_id_array(pending_candidate_ids_payload)
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
    status == 'failed' && failed_candidate_ids.any?
  end

  def pending_scope?
    selection_mode == 'pending_scope'
  end

  def selected_ids?
    selection_mode == 'selected_ids'
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
      selectionMode: selection_mode,
      active: active?,
      finished: finished?,
      retryable: retryable?,
      totalCandidates: total_candidates_count.to_i,
      pendingCandidates: pending_candidates_count.to_i,
      processedCandidates: processed_candidates_count.to_i,
      approvedCandidates: approved_candidates_count.to_i,
      duplicateCandidates: duplicate_candidates_count.to_i,
      skippedCandidates: skipped_candidates_count.to_i,
      failedCandidates: failed_candidates_count.to_i,
      completionPercentage: completion_percentage,
      currentCandidateId: current_candidate_id,
      currentCandidateName: current_candidate_name,
      lastProcessedCandidateId: last_processed_candidate_id,
      startedAt: started_at,
      lastAdvancedAt: last_advanced_at,
      finishedAt: finished_at,
      errorMessage: error_message
    }
  end

  private

  def normalized_id_array(value)
    Array(value).filter_map do |entry|
      id = entry.to_i
      id.positive? ? id : nil
    end.uniq
  end
end
