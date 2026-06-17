class BlackCoffeeFestivalImportRun < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze
  MODES = %w[dry_run import].freeze
  SOURCE_FAN_MUSIC_FEST = 'fanmusicfest'.freeze

  belongs_to :created_by, class_name: 'User', optional: true
  has_many :items,
           class_name: 'BlackCoffeeFestivalImportItem',
           foreign_key: :black_coffee_festival_import_run_id,
           dependent: :destroy,
           inverse_of: :run

  validates :source, :status, :mode, :strict_country_code, presence: true
  validates :source, inclusion: { in: [SOURCE_FAN_MUSIC_FEST] }
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }
  validates :max_pages, numericality: { greater_than: 0, less_than_or_equal_to: 13, only_integer: true }
  validates :max_details, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 500, only_integer: true }
  validates :request_delay_seconds, numericality: { greater_than_or_equal_to: 10, less_than_or_equal_to: 120 }

  scope :recent_first, -> { order(id: :desc) }

  def dry_run?
    mode == 'dry_run'
  end

  def import?
    mode == 'import'
  end

  def running?
    status == 'running'
  end

  def pending?
    status == 'pending'
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

  def status_label
    case status
    when 'running'
      'Procesando'
    when 'completed'
      'Completado'
    when 'failed'
      'Fallido'
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
    when 'cancelled'
      'secondary'
    when 'running'
      'info'
    else
      'warning'
    end
  end

  def mode_label
    dry_run? ? 'Dry run' : 'Importacion'
  end

  def progress_label
    "#{candidates_found_count.to_i} candidatos"
  end
end
