class VenueImage < ApplicationRecord
  belongs_to :venue
  mount_uploader :image, BlackCoffeeImageUploader

  validates :position, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :source_must_be_present
  validate :single_source_must_be_used
  validate :url_must_be_valid

  before_validation :normalize_url

  def public_url(base_url: nil)
    raw_value = external_image? ? url : image.url
    return if raw_value.blank?
    return "https:#{raw_value}" if raw_value.start_with?('//')
    return raw_value if raw_value.start_with?('http://', 'https://')
    return raw_value if base_url.blank?

    normalized_base = base_url.to_s.sub(%r{/*\z}, '')
    normalized_path = raw_value.start_with?('/') ? raw_value : "/#{raw_value}"
    "#{normalized_base}#{normalized_path}"
  end

  def external_image?
    url.present?
  end

  def uploaded_image?
    image?
  end

  def source_kind
    return :external if external_image?
    return :uploaded if uploaded_image?

    :unknown
  end

  private

  def normalize_url
    self.url = url.to_s.strip.presence
  end

  def source_must_be_present
    return if external_image? || uploaded_image?

    errors.add(:base, 'Debes indicar una imagen externa o subir un archivo')
  end

  def single_source_must_be_used
    return unless external_image? && uploaded_image?

    errors.add(:base, 'Cada imagen debe usar una sola fuente: URL o archivo')
  end

  def url_must_be_valid
    return unless external_image?
    return if URI::DEFAULT_PARSER.make_regexp(%w[http https]).match?(url)

    errors.add(:url, 'debe ser una URL http o https valida')
  end
end
