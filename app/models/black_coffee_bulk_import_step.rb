class BlackCoffeeBulkImportStep < ApplicationRecord
  STATUSES = %w[pending running completed failed split].freeze

  belongs_to :black_coffee_bulk_import,
             inverse_of: :import_steps
  belongs_to :black_coffee_import_run,
             optional: true,
             inverse_of: :bulk_import_steps

  validates :category, presence: true, inclusion: { in: Venue::CATEGORIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :depth, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :south_latitude, :south_longitude, :north_latitude, :north_longitude, presence: true, numericality: true

  scope :pending_first, -> { where(status: 'pending').order(:id) }

  def bounds_payload
    {
      low: {
        latitude: south_latitude.to_f,
        longitude: south_longitude.to_f
      },
      high: {
        latitude: north_latitude.to_f,
        longitude: north_longitude.to_f
      }
    }
  end

  def bounds_label
    format(
      '%.3f, %.3f → %.3f, %.3f',
      south_latitude.to_f,
      south_longitude.to_f,
      north_latitude.to_f,
      north_longitude.to_f
    )
  end
end
