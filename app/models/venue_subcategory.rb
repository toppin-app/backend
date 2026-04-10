class VenueSubcategory < ApplicationRecord
  CATEGORIES = Venue::CATEGORIES

  enum category: {
    bar: 'bar',
    restaurante: 'restaurante',
    escape_room: 'escape_room',
    cine: 'cine',
    cafeteria: 'cafeteria'
  }

  has_many :venues, dependent: :nullify

  validates :name, :category, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :name, uniqueness: { scope: :category, case_sensitive: false }

  before_validation :normalize_name
  before_create :assign_identifier

  def as_black_coffee_json
    {
      id: id,
      name: name,
      category: category,
      venueCount: venues.count
    }
  end

  private

  def normalize_name
    self.name = name.to_s.strip.downcase.presence
  end

  def assign_identifier
    self.id ||= "sub_#{SecureRandom.hex(6)}"
  end
end
