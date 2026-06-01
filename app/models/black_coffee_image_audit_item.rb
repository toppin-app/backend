class BlackCoffeeImageAuditItem < ApplicationRecord
  STATUSES = %w[pending ok failed skipped].freeze
  ERROR_TYPE_LABELS = {
    'missing_image' => 'Sin imagen guardada',
    'invalid_url' => 'URL invalida',
    'timeout' => 'Timeout',
    'network_error' => 'Error de red',
    'not_image' => 'No parece una imagen',
    'http_error' => 'Error HTTP',
    'temporary_google_photo_uri' => 'URL temporal de Google Places',
    'unknown_error' => 'Error desconocido'
  }.freeze

  belongs_to :batch,
             class_name: 'BlackCoffeeImageAuditBatch',
             foreign_key: :black_coffee_image_audit_batch_id,
             inverse_of: :items
  belongs_to :venue
  belongs_to :venue_image, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :checked, -> { where.not(status: 'pending') }
  scope :ordered, -> { order(:id) }

  def failed?
    status == 'failed'
  end

  def ok?
    status == 'ok'
  end

  def error_type_label
    ERROR_TYPE_LABELS[error_type.to_s] || error_type.to_s.presence || 'Sin detalle'
  end
end
