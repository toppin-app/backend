require 'uri'

class BlackCoffeeFestivalImportItem < ApplicationRecord
  STATUSES = %w[
    pending
    dry_run
    created
    updated
    duplicate
    skipped_outside_country
    skipped_duplicate
    skipped_invalid
    skipped_past
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

  def safe_source_url
    uri = URI.parse(source_url.to_s)
    host = uri.host.to_s.downcase
    return nil unless uri.scheme == 'https' && %w[fanmusicfest.com www.fanmusicfest.com].include?(host)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def coordinates_present?
    latitude.present? && longitude.present?
  end

  def map_url
    return nil unless coordinates_present?

    "https://www.google.com/maps/search/?api=1&query=#{latitude},#{longitude}"
  end

  def status_label
    case status
    when 'dry_run'
      'Simulado'
    when 'created'
      'Creado'
    when 'updated'
      'Actualizado'
    when 'duplicate', 'skipped_duplicate'
      'Duplicado'
    when 'skipped_outside_country'
      'Fuera de Espana'
    when 'skipped_invalid'
      'Invalido'
    when 'skipped_past'
      'Pasado'
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
    when 'created', 'updated'
      'success'
    when 'dry_run'
      'info'
    when 'duplicate', 'skipped_duplicate'
      'secondary'
    when 'skipped_outside_country', 'skipped_invalid'
      'warning'
    when 'skipped_past'
      'secondary'
    when 'failed'
      'danger'
    else
      'light'
    end
  end
end
