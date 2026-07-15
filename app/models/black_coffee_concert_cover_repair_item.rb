class BlackCoffeeConcertCoverRepairItem < ApplicationRecord
  STATUSES = %w[pending recovered_source recovered_search rejected failed skipped].freeze

  belongs_to :batch,
             class_name: 'BlackCoffeeConcertCoverRepairBatch',
             foreign_key: :black_coffee_concert_cover_repair_batch_id,
             inverse_of: :items
  belongs_to :venue, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :processed, -> { where.not(status: 'pending') }
  scope :recovered, -> { where(status: %w[recovered_source recovered_search]) }
  scope :ordered, -> { order(:id) }
  scope :recent_first, -> { order(id: :desc) }

  def status_label
    {
      'pending' => 'Pendiente',
      'recovered_source' => 'Recuperada desde origen',
      'recovered_search' => 'Recuperada por busqueda',
      'rejected' => 'Concierto rechazado',
      'failed' => 'Error interno',
      'skipped' => 'Saltado'
    }[status] || status.to_s.humanize
  end

  def status_badge_class
    {
      'pending' => 'warning',
      'recovered_source' => 'success',
      'recovered_search' => 'primary',
      'rejected' => 'danger',
      'failed' => 'danger',
      'skipped' => 'secondary'
    }[status] || 'light'
  end
end
