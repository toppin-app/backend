class VenueSubcategory < ApplicationRecord
  CATEGORIES = Venue::CATEGORIES

  enum category: {
    restaurante: 'restaurante',
    hotel: 'hotel',
    pub: 'pub',
    cine: 'cine',
    cafeteria: 'cafeteria',
    concierto: 'concierto',
    festival: 'festival',
    discoteca: 'discoteca',
    deportivo: 'deportivo',
    escape_room: 'escape_room'
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
