class BlackCoffeeImportRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :black_coffee_import_region,
             inverse_of: :import_runs
  belongs_to :black_coffee_import_region_category,
             optional: true,
             inverse_of: :import_runs
  belongs_to :black_coffee_bulk_import,
             optional: true,
             inverse_of: :import_runs
  has_many :import_candidates,
           class_name: 'BlackCoffeeImportCandidate',
           dependent: :destroy,
           inverse_of: :black_coffee_import_run
  has_many :bulk_import_steps,
           class_name: 'BlackCoffeeBulkImportStep',
           dependent: :nullify,
           inverse_of: :black_coffee_import_run
  has_many :photo_refresh_batches,
           class_name: 'BlackCoffeeImportPhotoRefreshBatch',
           dependent: :destroy,
           inverse_of: :black_coffee_import_run
  has_many :approval_batches,
           class_name: 'BlackCoffeeImportApprovalBatch',
           dependent: :destroy,
           inverse_of: :black_coffee_import_run

  validates :category, :status, presence: true
  validates :category, inclusion: { in: Venue::CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :limit, numericality: { greater_than: 0, less_than_or_equal_to: 60, only_integer: true }

  def reviewed_candidates_count
    approved_count.to_i + rejected_count.to_i + duplicate_count.to_i
  end

  def pending_review_count
    [candidate_count.to_i - reviewed_candidates_count, 0].max
  end

  def review_status_key
    return 'failed' if status == 'failed'
    return 'running' if status == 'running'
    return 'pending' if candidate_count.to_i.zero?
    return 'review_completed' if pending_review_count.zero?
    return 'review_in_progress' if reviewed_candidates_count.positive?

    'pending_review'
  end

  def review_status_label
    case review_status_key
    when 'failed'
      'Fallida'
    when 'running'
      'Importando'
    when 'review_completed'
      'Revisada'
    when 'review_in_progress'
      'En revision'
    when 'pending_review'
      'Pendiente de revisar'
    else
      'Pendiente'
    end
  end

  def review_status_badge_class
    case review_status_key
    when 'failed'
      'danger'
    when 'running'
      'primary'
    when 'review_completed'
      'success'
    when 'review_in_progress'
      'warning'
    else
      'secondary'
    end
  end

  def destroy_with_candidates!
    raise ActiveRecord::RecordNotDestroyed, 'No se puede eliminar una corrida con locales aprobados.' if import_candidates.where(status: 'approved').exists?

    region_category = black_coffee_import_region_category
    region = black_coffee_import_region

    ActiveRecord::Base.transaction do
      import_candidates.destroy_all
      destroy!

      if region_category.present?
        region_category.refresh_counts!
        refresh_last_imported_at!(region_category)
      else
        region.refresh_status!
      end
    end
  end

  def refresh_counts!
    counts = import_candidates.group(:status).count

    update!(
      candidate_count: counts.values.sum,
      duplicate_count: counts['duplicate'].to_i,
      approved_count: counts['approved'].to_i,
      rejected_count: counts['rejected'].to_i
    )

    black_coffee_import_region_category&.refresh_counts!
  end

  def apply_review_deltas!(approved_delta: 0, duplicate_delta: 0, rejected_delta: 0)
    approved_delta = approved_delta.to_i
    duplicate_delta = duplicate_delta.to_i
    rejected_delta = rejected_delta.to_i
    return if approved_delta.zero? && duplicate_delta.zero? && rejected_delta.zero?

    with_lock do
      update!(
        candidate_count: candidate_count.to_i.positive? ? candidate_count.to_i : import_candidates.count,
        approved_count: approved_count.to_i + approved_delta,
        duplicate_count: duplicate_count.to_i + duplicate_delta,
        rejected_count: rejected_count.to_i + rejected_delta
      )
    end

    black_coffee_import_region_category&.apply_review_deltas!(
      approved_delta: approved_delta,
      duplicate_delta: duplicate_delta,
      rejected_delta: rejected_delta
    )
  end

  private

  def refresh_last_imported_at!(region_category)
    latest_completed_run = region_category.import_runs.where(status: 'completed').order(created_at: :desc).first
    region_category.update!(last_imported_at: latest_completed_run&.created_at)
  end
end
