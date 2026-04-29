require 'digest'

class FixBlackCoffeeSubcategoryCatalog < ActiveRecord::Migration[6.0]
  FIXED_SUBCATEGORIES = {
    'restaurante' => %w[
      japonesa comida_china asiatica india italiana mexicana mediterranea tapas hamburgueseria brunch
      americana parrilla latina vegetariana_vegana
    ],
    'hotel' => %w[hotel hostal boutique business escapada resort bed_and_breakfast motel],
    'pub' => %w[cocteleria cerveceria vinoteca tapas rooftop lounge sports_bar],
    'cine' => %w[cine],
    'cafeteria' => %w[cafeteria artesanal panaderia pasteleria heladeria te],
    'concierto' => %w[indie pop_rock acustico musical],
    'festival' => %w[festival musical gastronomico urbano cultural convencion],
    'discoteca' => %w[discoteca club electro lounge rooftop],
    'deportivo' => %w[deporte gimnasio padel outdoor climbing tenis piscina golf arena],
    'escape_room' => %w[escape_room misterio terror aventura familiar]
  }.freeze

  LEGACY_ALIASES = {
    ['restaurante', 'restaurante'] => nil,
    ['pub', 'pub'] => nil,
    ['escape_room', 'escape room'] => ['escape_room', 'escape_room'],
    ['bar', 'cerveceria'] => ['pub', 'cerveceria'],
    ['bar', 'cocteleria'] => ['pub', 'cocteleria'],
    ['bar', 'tapas'] => ['pub', 'tapas']
  }.freeze

  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
  end

  class VenueSubcategoryRecord < ActiveRecord::Base
    self.table_name = 'venue_subcategories'
    self.primary_key = 'id'
  end

  def up
    reset_model_information!
    now = Time.current

    FIXED_SUBCATEGORIES.each do |category, names|
      names.each do |name|
        VenueSubcategoryRecord.find_or_create_by!(category: category, name: name) do |record|
          record.id = subcategory_id_for(category, name)
          record.created_at = now
          record.updated_at = now
        end
      end
    end

    normalize_legacy_subcategories!
  end

  def down
    # Catalog cleanup is intentionally not reversible because subcategories can
    # already be referenced by published venues.
  end

  private

  def reset_model_information!
    [VenueRecord, VenueSubcategoryRecord].each(&:reset_column_information)
  end

  def normalize_legacy_subcategories!
    fixed_pairs = FIXED_SUBCATEGORIES.flat_map { |category, names| names.map { |name| [category, name] } }

    VenueSubcategoryRecord.find_each do |subcategory|
      pair = [subcategory.category, subcategory.name]
      next if fixed_pairs.include?(pair)

      target_pair = LEGACY_ALIASES[pair]
      if target_pair
        target = VenueSubcategoryRecord.find_by!(category: target_pair.first, name: target_pair.second)
        VenueRecord.where(venue_subcategory_id: subcategory.id).update_all(venue_subcategory_id: target.id)
      else
        VenueRecord.where(venue_subcategory_id: subcategory.id).update_all(venue_subcategory_id: nil)
      end

      subcategory.destroy! unless VenueRecord.where(venue_subcategory_id: subcategory.id).exists?
    end
  end

  def subcategory_id_for(category, name)
    "sub_#{Digest::SHA256.hexdigest("#{category}:#{name}")[0, 12]}"
  end
end
