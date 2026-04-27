class BlackCoffeeImportRegion < ApplicationRecord
  STATUSES = %w[pending in_progress reviewed imported].freeze

  has_many :region_categories,
           class_name: 'BlackCoffeeImportRegionCategory',
           dependent: :destroy,
           inverse_of: :black_coffee_import_region
  has_many :import_runs,
           class_name: 'BlackCoffeeImportRun',
           dependent: :destroy,
           inverse_of: :black_coffee_import_region
  has_many :import_candidates,
           class_name: 'BlackCoffeeImportCandidate',
           dependent: :destroy,
           inverse_of: :black_coffee_import_region

  validates :name, :slug, :country_code, :status, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position, :name) }

  def category_state(category)
    region_categories.detect { |region_category| region_category.category == category.to_s }
  end

  def google_region_resource_name
    return unless has_attribute?(:google_region_place_id)

    normalized = google_region_place_id.to_s.strip
    return if normalized.blank?

    normalized.start_with?('places/') ? normalized : "places/#{normalized}"
  end

  def refresh_status!
    categories = region_categories.reload
    next_status =
      if categories.any? { |region_category| region_category.approved_count.positive? }
        'imported'
      elsif categories.any? { |region_category| region_category.pending_count.positive? }
        'reviewed'
      elsif categories.any? { |region_category| region_category.total_candidates.positive? }
        'reviewed'
      else
        'pending'
      end

    update!(status: next_status) if status != next_status
  end
end
