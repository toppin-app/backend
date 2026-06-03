class BlackCoffeeImageInternalizationItem < ApplicationRecord
  STATUSES = %w[pending converted failed skipped].freeze
  ERROR_TYPE_LABELS = {
    'missing_image' => 'Imagen eliminada',
    'not_external_link' => 'Ya no es un link externo',
    'missing_url' => 'URL vacia',
    'invalid_url' => 'URL invalida',
    'temporary_google_photo_uri' => 'URL temporal de Google Places',
    'timeout' => 'Timeout',
    'network_error' => 'Error de red',
    'http_error' => 'Error HTTP',
    'not_image' => 'No parece una imagen',
    'image_too_large' => 'Imagen demasiado grande',
    'empty_image' => 'Imagen vacia',
    'save_error' => 'Error guardando archivo',
    'unexpected_item_error' => 'Error interno de item',
    'unknown_error' => 'Error desconocido'
  }.freeze

  belongs_to :batch,
             class_name: 'BlackCoffeeImageInternalizationBatch',
             foreign_key: :black_coffee_image_internalization_batch_id,
             inverse_of: :items
  belongs_to :venue
  belongs_to :venue_image, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :converted, -> { where(status: 'converted') }
  scope :failed, -> { where(status: 'failed') }
  scope :skipped, -> { where(status: 'skipped') }
  scope :processed, -> { where.not(status: 'pending') }
  scope :ordered, -> { order(:id) }

  def converted?
    status == 'converted'
  end

  def failed?
    status == 'failed'
  end

  def skipped?
    status == 'skipped'
  end

  def error_type_label
    ERROR_TYPE_LABELS[error_type.to_s] || error_type.to_s.presence || 'Sin detalle'
  end
end
