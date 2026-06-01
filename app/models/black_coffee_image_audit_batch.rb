class BlackCoffeeImageAuditBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed rejected].freeze

  belongs_to :rejected_by, class_name: 'User', optional: true
  has_many :items,
           class_name: 'BlackCoffeeImageAuditItem',
           foreign_key: :black_coffee_image_audit_batch_id,
           dependent: :destroy,
           inverse_of: :batch

  validates :status, inclusion: { in: STATUSES }

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

  def rejected?
    status == 'rejected'
  end

  def finished?
    completed? || failed? || rejected?
  end

  def pending_checks?
    items.pending.exists?
  end

  def progress_percentage
    return 0 unless total_images.to_i.positive?

    ((checked_images.to_f / total_images) * 100).round
  end

  def failed_venue_ids
    items.failed.distinct.pluck(:venue_id)
  end

  def status_label
    case status
    when 'running'
      'Procesando'
    when 'completed'
      'Completado'
    when 'failed'
      'Fallido'
    when 'rejected'
      'Rechazos aplicados'
    else
      'Pendiente'
    end
  end

  def status_badge_class
    case status
    when 'completed'
      'success'
    when 'failed'
      'danger'
    when 'rejected'
      'dark'
    when 'running'
      'info'
    else
      'warning'
    end
  end
end
