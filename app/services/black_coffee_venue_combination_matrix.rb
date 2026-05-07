require 'set'

class BlackCoffeeVenueCombinationMatrix
  BLANK_LOCATION_KEY = '__sin_ubicacion__'.freeze

  Result = Struct.new(
    :states,
    :categories,
    :combination_keys,
    :populated_combination_keys,
    :venue_ids_by_combination,
    :empty_combination_keys,
    keyword_init: true
  )

  def self.build(scope: Venue.public_catalog_scope)
    new(scope: scope).build
  end

  def self.normalize_state_key(value)
    value.to_s.strip.presence || BLANK_LOCATION_KEY
  end

  def self.state_label(value)
    value.to_s == BLANK_LOCATION_KEY ? 'Sin ubicacion' : value.to_s
  end

  def self.location_key_for(city:, state:)
    normalize_state_key(city.presence || state)
  end

  def self.combination_label(state_key, category)
    "#{state_label(state_key)} · #{category}"
  end

  def initialize(scope:)
    @scope = scope
  end

  def build
    states = Set.new
    categories = Set.new
    venue_ids_by_combination = Hash.new { |hash, key| hash[key] = [] }

    @scope.select(:id, :city, :state, :category).find_each(batch_size: 1_000) do |venue|
      category = venue.category.to_s.strip.presence
      next if category.blank?

      state_key = self.class.location_key_for(city: venue.city.to_s.strip, state: venue.state.to_s.strip)
      states << state_key
      categories << category
      venue_ids_by_combination[[state_key, category]] << venue.id
    end

    ordered_states = states.to_a.sort
    ordered_categories = categories.to_a.sort
    populated_combination_keys = venue_ids_by_combination.keys.sort_by { |state_key, category| [state_key.to_s, category.to_s] }
    empty_combination_keys = []

    Result.new(
      states: ordered_states,
      categories: ordered_categories,
      combination_keys: populated_combination_keys,
      populated_combination_keys: populated_combination_keys,
      venue_ids_by_combination: venue_ids_by_combination,
      empty_combination_keys: empty_combination_keys
    )
  end
end
