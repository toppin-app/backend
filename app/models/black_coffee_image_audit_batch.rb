class BlackCoffeeImageAuditBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed rejected cancelled].freeze
  PROCESSING_MODES = %w[manual browser server].freeze
  REVIEW_STATUS_FILTER_ALL = 'all'.freeze
  REVIEW_STATUS_FILTER_LABELS = {
    Venue::REVIEW_STATUS_PENDING => 'Pendientes',
    Venue::REVIEW_STATUS_APPROVED => 'Aprobados',
    Venue::REVIEW_STATUS_REJECTED => 'Rechazados',
    REVIEW_STATUS_FILTER_ALL => 'Todos'
  }.freeze

  belongs_to :rejected_by, class_name: 'User', optional: true
  has_many :items,
           class_name: 'BlackCoffeeImageAuditItem',
           foreign_key: :black_coffee_image_audit_batch_id,
           dependent: :destroy,
           inverse_of: :batch

  validates :status, inclusion: { in: STATUSES }
  validates :processing_mode, inclusion: { in: PROCESSING_MODES }, if: -> { has_attribute?(:processing_mode) }
  validates :review_status_filter,
            inclusion: { in: ->(_batch) { BlackCoffeeImageAuditBatch.review_status_filter_values } },
            if: -> { has_attribute?(:review_status_filter) }

  scope :recent_first, -> { order(id: :desc) }

  def self.review_status_filter_values
    Venue::REVIEW_STATUSES + [REVIEW_STATUS_FILTER_ALL]
  end

  def self.review_status_filter_options
    review_status_filter_values.map do |value|
      [review_status_filter_label(value), value]
    end
  end

  def self.review_status_filter_label(value)
    REVIEW_STATUS_FILTER_LABELS[value.to_s] || value.to_s.presence || REVIEW_STATUS_FILTER_LABELS[Venue::REVIEW_STATUS_PENDING]
  end

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

  def cancelled?
    status == 'cancelled'
  end

  def finished?
    completed? || failed? || rejected? || cancelled?
  end

  def server_processing?
    has_attribute?(:processing_mode) &&
      processing_mode == 'server' &&
      running? &&
      pending_checks?
  end

  def server_processing_stale?
    server_processing? &&
      has_attribute?(:last_worker_heartbeat_at) &&
      last_worker_heartbeat_at.present? &&
      last_worker_heartbeat_at < 5.minutes.ago
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

  def review_status_filter_label
    self.class.review_status_filter_label(has_attribute?(:review_status_filter) ? review_status_filter : Venue::REVIEW_STATUS_PENDING)
  end

  def rejection_scope_label
    case has_attribute?(:review_status_filter) ? review_status_filter : Venue::REVIEW_STATUS_PENDING
    when Venue::REVIEW_STATUS_APPROVED
      'locales aprobados'
    when BlackCoffeeImageAuditBatch::REVIEW_STATUS_FILTER_ALL
      'locales pendientes o aprobados'
    when Venue::REVIEW_STATUS_REJECTED
      'ningun local ya rechazado'
    else
      'locales pendientes'
    end
  end

  def image_rejections_applicable?
    return true unless has_attribute?(:review_status_filter)

    review_status_filter != Venue::REVIEW_STATUS_REJECTED
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
    when 'cancelled'
      'Cancelado'
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
    when 'cancelled'
      'secondary'
    when 'running'
      'info'
    else
      'warning'
    end
  end

  def processing_mode_label
    case has_attribute?(:processing_mode) ? processing_mode : nil
    when 'server'
      'Servidor'
    when 'browser'
      'Navegador'
    else
      'Manual'
    end
  end
end
