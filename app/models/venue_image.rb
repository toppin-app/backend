class VenueImage < ApplicationRecord
  belongs_to :venue
  mount_uploader :image, BlackCoffeeImageUploader

  validates :position, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :image_must_be_present

  def public_url(base_url: nil)
    raw_url = image.url
    return if raw_url.blank?
    return "https:#{raw_url}" if raw_url.start_with?('//')
    return raw_url if raw_url.start_with?('http://', 'https://')
    return raw_url if base_url.blank?

    normalized_base = base_url.to_s.sub(%r{/*\z}, '')
    normalized_path = raw_url.start_with?('/') ? raw_url : "/#{raw_url}"
    "#{normalized_base}#{normalized_path}"
  end

  private

  def image_must_be_present
    return if self[:image].present?

    errors.add(:image, 'no puede estar en blanco')
  end
end
