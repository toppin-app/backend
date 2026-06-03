class BlackCoffeeImageInternalizationBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :created_by, class_name: 'User', optional: true
  has_many :items,
           class_name: 'BlackCoffeeImageInternalizationItem',
           foreign_key: :black_coffee_image_internalization_batch_id,
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

  def finished?
    completed? || failed?
  end

  def pending_items?
    items.pending.exists?
  end

  def progress_percentage
    return 0 unless total_images.to_i.positive?

    ((processed_images.to_f / total_images) * 100).round
  end

  def status_label
    case status
    when 'running'
      'Procesando'
    when 'completed'
      'Completado'
    when 'failed'
      'Fallido'
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
    when 'running'
      'info'
    else
      'warning'
    end
  end
end
