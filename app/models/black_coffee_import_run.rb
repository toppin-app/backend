class BlackCoffeeImportRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :black_coffee_import_region,
             inverse_of: :import_runs
  belongs_to :black_coffee_import_region_category,
             optional: true,
             inverse_of: :import_runs
  has_many :import_candidates,
           class_name: 'BlackCoffeeImportCandidate',
           dependent: :destroy,
           inverse_of: :black_coffee_import_run

  validates :category, :status, presence: true
  validates :category, inclusion: { in: Venue::CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :limit, numericality: { greater_than: 0, less_than_or_equal_to: 60, only_integer: true }

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
end
