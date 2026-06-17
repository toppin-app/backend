class BlackCoffeeFestivalImportItem < ApplicationRecord
  STATUSES = %w[
    pending
    dry_run
    created
    duplicate
    skipped_outside_country
    skipped_duplicate
    skipped_invalid
    failed
    cancelled
  ].freeze

  belongs_to :run,
             class_name: 'BlackCoffeeFestivalImportRun',
             foreign_key: :black_coffee_festival_import_run_id,
             inverse_of: :items
  belongs_to :venue, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(id: :desc) }
  scope :ordered, -> { order(:id) }

  def status_label
    case status
    when 'dry_run'
      'Simulado'
    when 'created'
      'Creado'
    when 'duplicate', 'skipped_duplicate'
      'Duplicado'
    when 'skipped_outside_country'
      'Fuera de Espana'
    when 'skipped_invalid'
      'Invalido'
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
    when 'created'
      'success'
    when 'dry_run'
      'info'
    when 'duplicate', 'skipped_duplicate'
      'secondary'
    when 'skipped_outside_country', 'skipped_invalid'
      'warning'
    when 'failed'
      'danger'
    else
      'light'
    end
  end
end
