require 'uri'

class BlackCoffeeConcertImportItem < ApplicationRecord
  STATUSES = %w[
    pending
    dry_run
    created
    created_pending_cover
    skipped_outside_country
    skipped_non_concert
    skipped_festival
    skipped_duplicate
    skipped_invalid
    skipped_past
    skipped_no_cover
    failed
    cancelled
  ].freeze

  belongs_to :run,
             class_name: 'BlackCoffeeConcertImportRun',
             foreign_key: :black_coffee_concert_import_run_id,
             inverse_of: :items
  belongs_to :venue, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(id: :desc) }
  scope :ordered, -> { order(:id) }

  def safe_source_url
    uri = URI.parse(source_url.to_s)
    host = uri.host.to_s.downcase
    return nil unless uri.scheme == 'https' && %w[songkick.com www.songkick.com].include?(host)

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
    when 'created_pending_cover'
      'Creado pendiente de portada'
    when 'skipped_outside_country'
      'Fuera de Espana'
    when 'skipped_non_concert'
      'No concierto'
    when 'skipped_festival'
      'No concierto'
    when 'skipped_duplicate'
      'Duplicado'
    when 'skipped_invalid'
      'Invalido'
    when 'skipped_past'
      'Pasado'
    when 'skipped_no_cover'
      'Sin portada'
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
    when 'created_pending_cover'
      'warning'
    when 'dry_run'
      'info'
    when 'skipped_duplicate', 'skipped_non_concert', 'skipped_festival', 'skipped_past'
      'secondary'
    when 'skipped_outside_country', 'skipped_invalid', 'skipped_no_cover'
      'warning'
    when 'failed'
      'danger'
    else
      'light'
    end
  end
end
