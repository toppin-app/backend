class BlackCoffeeImportRegionCategory < ApplicationRecord
  STATUSES = %w[pending pending_review reviewed imported].freeze

  belongs_to :black_coffee_import_region,
             inverse_of: :region_categories
  has_many :import_runs,
           class_name: 'BlackCoffeeImportRun',
           dependent: :nullify,
           inverse_of: :black_coffee_import_region_category
  has_many :import_candidates,
           class_name: 'BlackCoffeeImportCandidate',
           dependent: :nullify,
           inverse_of: :black_coffee_import_region_category

  validates :category, :status, presence: true
  validates :category, inclusion: { in: Venue::CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :category, uniqueness: { scope: :black_coffee_import_region_id }

  def google_total_known?
    has_attribute?(:google_total_count) && google_total_count.present?
  end

  def google_missing_count
    return unless google_total_known?

    [google_total_count.to_i - approved_count.to_i, 0].max
  end

  def google_import_percentage
    return unless google_total_count.to_i.positive?

    ((approved_count.to_f / google_total_count.to_i) * 100).round
  end

  def refresh_counts!
    counts = import_candidates.group(:status).count
    next_status =
      if counts['approved'].to_i.positive?
        'imported'
      elsif counts['pending'].to_i.positive?
        'pending_review'
      elsif counts.values.sum.positive?
        'reviewed'
      else
        'pending'
      end

    update!(
      status: next_status,
      total_candidates: counts.values.sum,
      pending_count: counts['pending'].to_i,
      approved_count: counts['approved'].to_i,
      rejected_count: counts['rejected'].to_i,
      duplicate_count: counts['duplicate'].to_i
    )

    black_coffee_import_region.refresh_status!
  end
end
