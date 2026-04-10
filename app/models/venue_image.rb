class VenueImage < ApplicationRecord
  belongs_to :venue

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :position, numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
