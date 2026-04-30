class BlackCoffeeBulkImport < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze

  belongs_to :black_coffee_import_region,
             inverse_of: :bulk_imports
  has_many :import_steps,
           class_name: 'BlackCoffeeBulkImportStep',
           dependent: :destroy,
           inverse_of: :black_coffee_bulk_import
  has_many :import_runs,
           class_name: 'BlackCoffeeImportRun',
           dependent: :nullify,
           inverse_of: :black_coffee_bulk_import
  has_many :import_candidates,
           through: :import_runs,
           source: :import_candidates

  validates :status, inclusion: { in: STATUSES }
  validates :max_depth, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :min_cell_size_meters, :step_limit, numericality: { greater_than: 0, only_integer: true }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def categories
    Array(categories_payload).presence || GooglePlacesBlackCoffeeClient.importable_categories
  end

  def active?
    status.in?(%w[pending running])
  end

  def finished?
    status.in?(%w[completed failed cancelled])
  end

  def completion_percentage
    total = total_steps.to_i
    return 0 if total.zero?

    processed = completed_steps_count.to_i + split_steps_count.to_i + failed_steps_count.to_i
    ((processed.to_f / total) * 100).round
  end

  def category_summaries
    step_counts = import_steps.group(:category, :status).count
    runs_by_category = BlackCoffeeImportRun.where(black_coffee_bulk_import_id: id).to_a.index_by(&:category)

    categories.map do |category|
      counts = {
        pending: step_counts[[category, 'pending']].to_i,
        running: step_counts[[category, 'running']].to_i,
        completed: step_counts[[category, 'completed']].to_i,
        split: step_counts[[category, 'split']].to_i,
        failed: step_counts[[category, 'failed']].to_i
      }
      total_steps_for_category = counts.values.sum
      processed_steps = total_steps_for_category - counts[:pending] - counts[:running]
      run = runs_by_category[category]

      {
        category: category,
        label: GooglePlacesBlackCoffeeClient.config_for(category)[:label],
        total_steps: total_steps_for_category,
        processed_steps: processed_steps,
        pending_steps: counts[:pending],
        running_steps: counts[:running],
        completed_steps: counts[:completed],
        split_steps: counts[:split],
        failed_steps: counts[:failed],
        progress_percentage: total_steps_for_category.zero? ? 0 : ((processed_steps.to_f / total_steps_for_category) * 100).round,
        run_id: run&.id,
        run_status: run&.status,
        found_count: run&.found_count.to_i,
        candidate_count: run&.candidate_count.to_i,
        duplicate_count: run&.duplicate_count.to_i
      }
    end
  end

  def as_progress_json
    {
      id: id,
      status: status,
      active: active?,
      finished: finished?,
      region: {
        id: black_coffee_import_region_id,
        name: black_coffee_import_region.name,
        slug: black_coffee_import_region.slug
      },
      geometryStrategy: geometry_strategy,
      categories: categories,
      bounds: bounds_payload || {},
      completionPercentage: completion_percentage,
      totalSteps: total_steps.to_i,
      pendingSteps: pending_steps_count.to_i,
      runningSteps: running_steps_count.to_i,
      completedSteps: completed_steps_count.to_i,
      splitSteps: split_steps_count.to_i,
      failedSteps: failed_steps_count.to_i,
      saturatedSteps: saturated_steps_count.to_i,
      completedCategories: completed_categories_count.to_i,
      requestsCount: requests_count.to_i,
      foundCount: found_count.to_i,
      savedCandidatesCount: saved_candidates_count.to_i,
      duplicateCandidatesCount: duplicate_candidates_count.to_i,
      errorCount: error_count.to_i,
      currentCategory: current_category,
      currentCategoryLabel: current_category.present? ? GooglePlacesBlackCoffeeClient.config_for(current_category)[:label] : nil,
      currentCellLabel: current_cell_label,
      startedAt: started_at,
      lastAdvancedAt: last_advanced_at,
      finishedAt: finished_at,
      errorMessage: error_message,
      categorySummaries: category_summaries
    }
  end

  def refresh_progress!
    step_counts = import_steps.group(:status).count
    running_step = import_steps.where(status: 'running').order(:updated_at).last
    next_pending_step = import_steps.where(status: 'pending').order(:id).first
    run_scope = BlackCoffeeImportRun.where(black_coffee_bulk_import_id: id)
    next_category = finished? ? nil : (running_step&.category || next_pending_step&.category)
    next_cell_label = finished? ? nil : (running_step&.bounds_label || next_pending_step&.bounds_label)

    update!(
      total_steps: step_counts.values.sum,
      pending_steps_count: step_counts['pending'].to_i,
      running_steps_count: step_counts['running'].to_i,
      completed_steps_count: step_counts['completed'].to_i,
      split_steps_count: step_counts['split'].to_i,
      failed_steps_count: step_counts['failed'].to_i,
      saturated_steps_count: import_steps.where(saturated: true).count,
      completed_categories_count: category_summaries.count { |summary| summary[:pending_steps].zero? && summary[:running_steps].zero? && summary[:total_steps].positive? },
      requests_count: import_steps.sum(:request_count),
      found_count: run_scope.sum(:found_count),
      saved_candidates_count: run_scope.sum(:candidate_count),
      duplicate_candidates_count: import_steps.sum(:duplicate_count),
      error_count: step_counts['failed'].to_i,
      current_category: next_category,
      current_cell_label: next_cell_label
    )
  end
end
