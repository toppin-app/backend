class BlackCoffeeReviewBatch < ApplicationRecord
  STATUSES = %w[open completed cancelled].freeze

  belongs_to :reviewed_by, class_name: 'User', optional: true
  has_many :review_items,
           class_name: 'BlackCoffeeReviewBatchItem',
           foreign_key: :black_coffee_review_batch_id,
           dependent: :destroy,
           inverse_of: :review_batch
  has_many :venues, through: :review_items

  validates :status, inclusion: { in: STATUSES }
  validates :batch_size, :total_places, :approved_count, :rejected_count,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :open, -> { where(status: 'open') }
  scope :completed, -> { where(status: 'completed') }
  scope :recent_first, -> { order(created_at: :desc) }

  def completed?
    status == 'completed'
  end

  def open?
    status == 'open'
  end

  def filters
    filters_payload.respond_to?(:with_indifferent_access) ? filters_payload.with_indifferent_access : {}
  end

  def filters_summary
    parts = []
    parts << "Categoria: #{filters[:category]}" if filters[:category].present?
    parts << "Subcategoria: #{filters[:subcategory]}" if filters[:subcategory].present?
    parts.presence&.join(' · ') || 'Sin filtros'
  end

  def status_label
    case status
    when 'completed'
      'Completado'
    when 'cancelled'
      'Cancelado'
    else
      'Abierto'
    end
  end

  def status_badge_class
    case status
    when 'completed'
      'success'
    when 'cancelled'
      'secondary'
    else
      'warning'
    end
  end
end
