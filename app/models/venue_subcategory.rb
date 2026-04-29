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
  validate :name_is_part_of_fixed_taxonomy

  before_validation :normalize_name
  before_create :assign_identifier

  def as_black_coffee_json
    {
      id: id,
      name: name,
      label: BlackCoffeeTaxonomy.label_for(category, name),
      category: category,
      googleTypes: Array(BlackCoffeeTaxonomy.option_for(category, name)&.fetch(:google_types, [])),
      venueCount: venues.count
    }
  end

  private

  def normalize_name
    self.name = name.to_s.strip.downcase.presence
  end

  def assign_identifier
    self.id ||= BlackCoffeeTaxonomy.subcategory_id(category, name)
  end

  def name_is_part_of_fixed_taxonomy
    return if category.blank? || name.blank?
    return if BlackCoffeeTaxonomy.valid_subcategory?(category, name)

    errors.add(:name, 'no forma parte del catalogo fijo de Black Coffee')
  end
end
