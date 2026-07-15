class BlackCoffeeConcertCoverRepairBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze
  REVIEW_STATUS_FILTERS = %w[approved pending active].freeze

  belongs_to :created_by, class_name: 'User', optional: true
  has_many :items,
           class_name: 'BlackCoffeeConcertCoverRepairItem',
           foreign_key: :black_coffee_concert_cover_repair_batch_id,
           dependent: :destroy,
           inverse_of: :batch

  validates :status, inclusion: { in: STATUSES }
  validates :review_status_filter, inclusion: { in: REVIEW_STATUS_FILTERS }

  scope :recent_first, -> { order(id: :desc) }

  def pending?
    status == 'pending'
  end

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def cancelled?
    status == 'cancelled'
  end

  def finished?
    completed? || failed? || cancelled?
  end

  def pending_items?
    items.pending.exists?
  end

  def progress_percentage
    return 0 unless total_venues.to_i.positive?

    ((processed_venues.to_f / total_venues) * 100).round
  end

  def status_label
    {
      'pending' => 'Pendiente',
      'running' => 'Procesando',
      'completed' => 'Completado',
      'failed' => 'Fallido',
      'cancelled' => 'Cancelado'
    }[status] || status.to_s.humanize
  end

  def status_badge_class
    {
      'pending' => 'warning',
      'running' => 'info',
      'completed' => 'success',
      'failed' => 'danger',
      'cancelled' => 'secondary'
    }[status] || 'light'
  end

  def review_status_filter_label
    {
      'approved' => 'Aprobados',
      'pending' => 'Pendientes',
      'active' => 'Aprobados y pendientes'
    }[review_status_filter] || review_status_filter.to_s.humanize
  end
end
