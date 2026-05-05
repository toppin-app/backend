require 'set'

class BlackCoffeeGoogleTagCatalog
  CORE_TYPES = %w[
    restaurant bar pub cafe coffee_shop cafeteria hotel hostel motel bed_and_breakfast guest_house resort_hotel inn
    extended_stay_hotel movie_theater night_club dance_hall sports_complex stadium arena gym fitness_center sports_club
    athletic_field sports_activity_location amusement_center butcher_shop food_store grocery_store supermarket
    convenience_store discount_supermarket warehouse_store wholesaler store manufacturer market farmers_market bakery
    pastry_shop dessert_shop cake_shop deli liquor_store fish_store seafood_market tea_store tea_house winery wine_bar
    cocktail_bar lounge_bar sports_bar bar_and_grill gastropub brunch_restaurant breakfast_restaurant diner
    steak_house mediterranean_restaurant spanish_restaurant tapas_restaurant italian_restaurant pizza_restaurant
    sushi_restaurant japanese_restaurant mexican_restaurant burger_restaurant hamburger_restaurant vegan_restaurant
    vegetarian_restaurant tennis_court swimming_pool golf_course indoor_golf_course
  ].freeze

  def self.all_tags
    tags = Set.new

    CORE_TYPES.each { |tag| tags << normalize(tag) }
    tags.merge(tags_from_category_config)
    tags.merge(tags_from_taxonomy)
    tags.merge(tags_from_storage)

    tags.reject(&:blank?).to_a.sort
  end

  def self.tags_from_category_config
    GooglePlacesBlackCoffeeClient::CATEGORY_CONFIG.values.flat_map do |config|
      Array(config[:included_type]) +
        Array(config[:google_types]) +
        Array(config[:aggregate_types]) +
        Array(config[:aggregate_primary_types]) +
        Array(config[:aggregate_excluded_types]) +
        Array(config[:aggregate_excluded_primary_types])
    end.map { |tag| normalize(tag) }
  end

  def self.tags_from_taxonomy
    BlackCoffeeTaxonomy.subcategory_options.flat_map { |entry| Array(entry[:google_types]) }
                       .map { |tag| normalize(tag) }
  end

  def self.tags_from_storage
    return [] unless storage_available?

    collected = Set.new

    Venue.where.not(google_primary_type: [nil, '']).pluck(:google_primary_type).each { |tag| collected << normalize(tag) }
    Venue.where.not(tags: nil).pluck(:tags).each do |tags|
      normalize_array_payload(tags).each { |tag| collected << normalize(tag) }
    end

    BlackCoffeeImportCandidate.order(id: :desc).limit(5_000).pluck(:raw_payload).each do |payload|
      normalized_payload = normalize_hash_payload(payload)
      collected << normalize(BlackCoffeeTaxonomy.google_primary_type_for_place(normalized_payload))
      BlackCoffeeTaxonomy.google_tags_for_place(normalized_payload).each { |tag| collected << normalize(tag) }
    end

    collected.to_a
  end

  def self.storage_available?
    ActiveRecord::Base.connection.data_source_exists?('black_coffee_import_candidates') &&
      ActiveRecord::Base.connection.data_source_exists?('venues')
  rescue StandardError
    false
  end

  def self.normalize(value)
    BlackCoffeeTaxonomy.normalize_google_tag(value)
  end

  def self.normalize_array_payload(value)
    case value
    when Array
      value
    when String
      JSON.parse(value)
    else
      []
    end
  rescue JSON::ParserError
    []
  end

  def self.normalize_hash_payload(value)
    payload =
      case value
      when String
        JSON.parse(value)
      when Hash
        value
      else
        {}
      end

    payload.respond_to?(:with_indifferent_access) ? payload.with_indifferent_access : payload
  rescue JSON::ParserError
    {}
  end
end
