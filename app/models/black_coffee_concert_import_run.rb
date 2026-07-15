class BlackCoffeeConcertImportRun < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze
  MODES = %w[dry_run import].freeze
  SOURCE_SONGKICK = 'songkick'.freeze
  IMPORT_ORIGINS = %w[dashboard cron].freeze
  IMPORT_ORIGIN_DASHBOARD = 'dashboard'.freeze
  IMPORT_ORIGIN_CRON = 'cron'.freeze

  belongs_to :created_by, class_name: 'User', optional: true
  has_many :items,
           class_name: 'BlackCoffeeConcertImportItem',
           foreign_key: :black_coffee_concert_import_run_id,
           dependent: :destroy,
           inverse_of: :run

  validates :source, :status, :mode, :strict_country_code, presence: true
  validates :source, inclusion: { in: [SOURCE_SONGKICK] }
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }
  validates :import_origin, inclusion: { in: IMPORT_ORIGINS }, if: -> { has_attribute?(:import_origin) }
  validates :max_pages_per_source, numericality: { greater_than: 0, less_than_or_equal_to: 25, only_integer: true }
  validates :max_events, numericality: { greater_than: 0, less_than_or_equal_to: 10_000, only_integer: true }
  validates :request_delay_seconds, numericality: { greater_than_or_equal_to: 10, less_than_or_equal_to: 120 }

  scope :recent_first, -> { order(id: :desc) }

  def dry_run?
    mode == 'dry_run'
  end

  def import?
    mode == 'import'
  end

  def dashboard_import?
    !has_attribute?(:import_origin) || import_origin.to_s == IMPORT_ORIGIN_DASHBOARD
  end

  def cron_import?
    has_attribute?(:import_origin) && import_origin.to_s == IMPORT_ORIGIN_CRON
  end

  def publish_immediately?
    import? && dashboard_import?
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

  def source_paths_list
    source_paths.to_s.lines.map(&:strip).reject(&:blank?).uniq
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
    dry_run? ? 'Dry run' : 'Importación'
  end

  def origin_label
    cron_import? ? 'Cron' : 'Dashboard'
  end

  def non_concert_skipped_total
    if has_attribute?(:non_concert_skipped_count)
      non_concert_skipped_count.to_i + festival_skipped_count.to_i
    else
      festival_skipped_count.to_i
    end
  end

  def progress_label
    "#{candidates_found_count.to_i} candidatos"
  end
end
