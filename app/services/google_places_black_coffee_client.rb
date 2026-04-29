require 'json'
require 'net/http'
require 'uri'

class GooglePlacesBlackCoffeeClient
  class MissingApiKeyError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = 'https://places.googleapis.com/v1/places:searchText'.freeze
  PHOTO_HOST = 'places.googleapis.com'.freeze
  MAX_PAGE_SIZE = 20
  MAX_RESULTS = 60
  MAX_PHOTOS_PER_PLACE = 3
  EXCLUDED_IMPORT_CATEGORIES = %w[concierto].freeze
  FIELD_MASK = %w[
    places.id
    places.name
    places.displayName
    places.formattedAddress
    places.location
    places.types
    places.primaryType
    places.primaryTypeDisplayName
    places.rating
    places.userRatingCount
    places.googleMapsUri
    places.websiteUri
    places.nationalPhoneNumber
    places.addressComponents
    places.regularOpeningHours
    places.photos
    nextPageToken
  ].join(',').freeze
  SUBCATEGORY_TYPE_MAP = {
    'restaurante' => {
      'american_restaurant' => 'americana',
      'barbecue_restaurant' => 'americana',
      'steak_house' => 'americana',
      'breakfast_restaurant' => 'brunch',
      'brunch_restaurant' => 'brunch',
      'chinese_restaurant' => 'comida_china',
      'hamburger_restaurant' => 'hamburgueseria',
      'indian_restaurant' => 'india',
      'italian_restaurant' => 'italiana',
      'pizza_restaurant' => 'italiana',
      'japanese_restaurant' => 'japonesa',
      'ramen_restaurant' => 'japonesa',
      'sushi_restaurant' => 'japonesa',
      'greek_restaurant' => 'mediterranea',
      'lebanese_restaurant' => 'mediterranea',
      'mediterranean_restaurant' => 'mediterranea',
      'middle_eastern_restaurant' => 'mediterranea',
      'seafood_restaurant' => 'mediterranea',
      'turkish_restaurant' => 'mediterranea',
      'mexican_restaurant' => 'mexicana',
      'spanish_restaurant' => 'tapas'
    },
    'pub' => {
      'bar' => 'cocteleria',
      'bar_and_grill' => 'tapas',
      'pub' => 'cerveceria',
      'wine_bar' => 'cocteleria'
    }
  }.freeze
  SUBCATEGORY_TEXT_RULES = {
    'restaurante' => [
      ['japonesa', %w[sushi ramen izakaya japones japonesa japon maki]],
      ['mexicana', %w[mexican mexicana mexicano tacos taco taqueria burrito]],
      ['italiana', %w[italian italiana italiano pizza pizzeria trattoria pasta]],
      ['hamburgueseria', %w[burger hamburguesa hamburgueseria]],
      ['brunch', %w[brunch breakfast desayuno]],
      ['comida_china', ['chino', 'china', 'chinese', 'wok', 'dim sum']],
      ['india', %w[indian india hindu curry]],
      ['tapas', %w[tapas taberna taperia pinchos pintxos]],
      ['mediterranea', %w[mediterraneo mediterranea marisqueria arroceria paella seafood]],
      ['americana', %w[american americana bbq barbecue steakhouse asador grill]]
    ],
    'pub' => [
      ['cerveceria', %w[cerveceria cerveza beer pub]],
      ['cocteleria', %w[coctel cocteleria cocktail cocktails wine vino]],
      ['tapas', %w[tapas taberna gastrobar]]
    ]
  }.freeze

  CATEGORY_CONFIG = {
    'restaurante' => {
      label: 'Restaurantes',
      query: 'restaurantes',
      included_type: 'restaurant',
      google_types: %w[restaurant food],
      aggregate_types: %w[restaurant],
      subcategory: nil
    },
    'hotel' => {
      label: 'Hoteles',
      query: 'hoteles',
      included_type: 'lodging',
      google_types: %w[lodging],
      aggregate_primary_types: %w[hotel hostel motel bed_and_breakfast guest_house resort_hotel inn extended_stay_hotel],
      subcategory: 'hotel'
    },
    'pub' => {
      label: 'Pubs',
      query: 'pubs bares coctelerias',
      included_type: 'bar',
      google_types: %w[bar],
      aggregate_types: %w[pub bar bar_and_grill wine_bar],
      subcategory: nil
    },
    'cine' => {
      label: 'Cines',
      query: 'cines',
      included_type: 'movie_theater',
      google_types: %w[movie_theater],
      aggregate_types: %w[movie_theater],
      subcategory: 'cine'
    },
    'cafeteria' => {
      label: 'Cafeterias',
      query: 'cafeterias',
      included_type: 'cafe',
      google_types: %w[cafe],
      aggregate_types: %w[cafe coffee_shop cafeteria],
      subcategory: 'cafeteria'
    },
    'concierto' => {
      label: 'Conciertos',
      query: 'salas de conciertos musica en vivo',
      google_types: %w[event_venue performing_arts_theater],
      aggregate_types: %w[concert_hall event_venue performing_arts_theater auditorium],
      subcategory: 'musica en vivo'
    },
    'festival' => {
      label: 'Festivales',
      query: 'festivales eventos',
      google_types: %w[event_venue],
      aggregate_types: %w[event_venue amphitheatre convention_center cultural_center],
      subcategory: 'festival'
    },
    'discoteca' => {
      label: 'Discotecas',
      query: 'discotecas clubs nocturnos',
      included_type: 'night_club',
      google_types: %w[night_club],
      aggregate_types: %w[night_club dance_hall],
      subcategory: 'discoteca'
    },
    'deportivo' => {
      label: 'Deportivos',
      query: 'planes deportivos centros deportivos',
      included_type: 'gym',
      google_types: %w[gym stadium sports_complex],
      aggregate_types: %w[sports_complex stadium arena gym fitness_center sports_club athletic_field sports_activity_location],
      subcategory: 'deporte'
    },
    'escape_room' => {
      label: 'Escape rooms',
      query: 'escape room',
      google_types: %w[amusement_center],
      aggregate_types: %w[amusement_center],
      subcategory: 'escape room'
    }
  }.freeze

  def self.api_key
    ENV['GOOGLE_PLACES_API_KEY'].presence || ENV['GOOGLE_MAPS_API_KEY'].presence
  end

  def self.category_options
    importable_categories.map do |category|
      [CATEGORY_CONFIG.dig(category, :label) || category.humanize, category]
    end
  end

  def self.importable_categories
    Venue::CATEGORIES - EXCLUDED_IMPORT_CATEGORIES
  end

  def self.config_for(category)
    CATEGORY_CONFIG.fetch(category.to_s)
  end

  def initialize(api_key: self.class.api_key)
    @api_key = api_key
  end

  def search(region:, category:, limit:, query_override: nil)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    normalized_category = category.to_s
    config = self.class.config_for(normalized_category)
    requested_limit = [[limit.to_i, 1].max, MAX_RESULTS].min
    query = build_query(region: region, config: config, query_override: query_override)
    places = fetch_places(query: query, config: config, limit: requested_limit)

    places.first(requested_limit).map do |place|
      place_to_candidate_attributes(
        place,
        region: region,
        category: normalized_category,
        subcategory: config[:subcategory]
      )
    end
  end

  private

  def build_query(region:, config:, query_override:)
    raw_query = query_override.to_s.strip.presence || config.fetch(:query)
    "#{raw_query} en #{region.name}, Espana"
  end

  def fetch_places(query:, config:, limit:)
    places = []
    next_page_token = nil

    loop do
      remaining = limit - places.size
      break if remaining <= 0

      body = {
        textQuery: query,
        languageCode: 'es',
        regionCode: 'ES',
        pageSize: [remaining, MAX_PAGE_SIZE].min
      }
      body[:includedType] = config[:included_type] if config[:included_type].present?
      body[:pageToken] = next_page_token if next_page_token.present?

      payload = post_json(BASE_URL, body)
      places.concat(Array(payload['places']))
      next_page_token = payload['nextPageToken'].presence
      break if next_page_token.blank? || places.size >= limit
    end

    places
  end

  def post_json(url, body)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-Goog-Api-Key'] = @api_key
    request['X-Goog-FieldMask'] = FIELD_MASK
    request.body = JSON.generate(body)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 20, open_timeout: 10) do |http|
      http.request(request)
    end

    parsed = JSON.parse(response.body.presence || '{}')
    return parsed if response.is_a?(Net::HTTPSuccess)

    message = parsed.dig('error', 'message').presence || response.message
    raise RequestError, "Google Places respondio #{response.code}: #{message}"
  rescue JSON::ParserError
    raise RequestError, 'Google Places devolvio una respuesta no JSON.'
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise RequestError, 'Google Places no respondio a tiempo.'
  end

  def place_to_candidate_attributes(place, region:, category:, subcategory:)
    photos = Array(place['photos']).first(MAX_PHOTOS_PER_PLACE)
    address_components = place['addressComponents']

    {
      google_place_id: place['id'].presence || place['name'].to_s.split('/').last,
      name: place.dig('displayName', 'text').presence || 'Local sin nombre',
      address: place['formattedAddress'],
      city: city_from_components(address_components).presence || region.name,
      postal_code: address_component_value(address_components, 'postal_code'),
      state: address_component_value(address_components, 'administrative_area_level_1'),
      country: address_component_value(address_components, 'country'),
      country_code: address_component_value(address_components, 'country', key: 'shortText'),
      category: category,
      subcategory: resolved_subcategory_for(place, category: category, fallback: subcategory),
      latitude: place.dig('location', 'latitude'),
      longitude: place.dig('location', 'longitude'),
      rating: place['rating'],
      user_ratings_total: place['userRatingCount'],
      website: place['websiteUri'],
      phone: place['nationalPhoneNumber'],
      google_maps_uri: place['googleMapsUri'],
      image_urls: photos.filter_map { |photo| photo_uri_for(photo['name']) },
      google_photo_references: photos.map { |photo| photo_reference_payload(photo) },
      author_attributions: photos.flat_map { |photo| Array(photo['authorAttributions']) },
      raw_payload: place
    }
  end

  def resolved_subcategory_for(place, category:, fallback:)
    explicit_match = subcategory_from_place_types(place, category)
    text_match = subcategory_from_place_text(place, category)

    [explicit_match, text_match].compact.each do |candidate|
      normalized = normalize_subcategory_name(candidate)
      return normalized if known_subcategory?(category, normalized)
    end

    fallback
  end

  def subcategory_from_place_types(place, category)
    map = SUBCATEGORY_TYPE_MAP.fetch(category.to_s, {})
    return if map.blank?

    types = [place['primaryType'], Array(place['types'])].flatten.compact.map do |type|
      type.to_s.downcase
    end
    types.filter_map { |type| map[type] }.first
  end

  def subcategory_from_place_text(place, category)
    rules = SUBCATEGORY_TEXT_RULES.fetch(category.to_s, [])
    return if rules.blank?

    text = normalized_match_text(
      [
        place.dig('displayName', 'text'),
        place.dig('primaryTypeDisplayName', 'text'),
        place['primaryType'],
        Array(place['types']).join(' ')
      ].compact.join(' ')
    )

    rules.find do |_subcategory, keywords|
      keywords.any? { |keyword| text.include?(normalized_match_text(keyword)) }
    end&.first
  end

  def known_subcategory?(category, subcategory)
    names = known_subcategory_names(category)
    names.blank? || names.include?(subcategory)
  end

  def known_subcategory_names(category)
    @known_subcategory_names ||= {}
    @known_subcategory_names[category.to_s] ||=
      VenueSubcategory
      .where(category: category.to_s)
      .pluck(:name)
      .map { |name| normalize_subcategory_name(name) }
      .compact
  rescue StandardError => e
    Rails.logger.warn("Black Coffee subcategory lookup skipped: #{e.message}") if defined?(Rails)
    []
  end

  def normalize_subcategory_name(value)
    value.to_s.strip.downcase.presence
  end

  def normalized_match_text(value)
    I18n.transliterate(value.to_s).downcase
  rescue StandardError
    value.to_s.downcase
  end

  def city_from_components(components)
    preferred_types = %w[locality postal_town administrative_area_level_2 administrative_area_level_1]
    component = preferred_types.filter_map do |type|
      Array(components).find { |entry| Array(entry['types']).include?(type) }
    end.first

    component&.dig('longText') || component&.dig('shortText')
  end

  def address_component_value(components, type, key: 'longText')
    component = Array(components).find { |entry| Array(entry['types']).include?(type) }
    component&.dig(key).presence || component&.dig('longText').presence || component&.dig('shortText')
  end

  def photo_reference_payload(photo)
    {
      name: photo['name'],
      width: photo['widthPx'],
      height: photo['heightPx'],
      author_attributions: Array(photo['authorAttributions'])
    }
  end

  def photo_uri_for(photo_name)
    return if photo_name.blank?

    uri = URI::HTTPS.build(
      host: PHOTO_HOST,
      path: "/v1/#{photo_name}/media",
      query: URI.encode_www_form(
        key: @api_key,
        maxWidthPx: 1200,
        skipHttpRedirect: true
      )
    )
    payload = get_json(uri)
    normalize_photo_uri(payload['photoUri'])
  rescue RequestError => e
    Rails.logger.warn("Black Coffee Google photo skipped: #{e.message}") if defined?(Rails)
    nil
  end

  def get_json(uri)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    parsed = JSON.parse(response.body.presence || '{}')
    return parsed if response.is_a?(Net::HTTPSuccess)

    message = parsed.dig('error', 'message').presence || response.message
    raise RequestError, "Google Places respondio #{response.code}: #{message}"
  rescue JSON::ParserError
    raise RequestError, 'Google Places devolvio una respuesta de foto no JSON.'
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise RequestError, 'Google Places Photos no respondio a tiempo.'
  end

  def normalize_photo_uri(photo_uri)
    value = photo_uri.to_s.strip
    return if value.blank?
    return "https:#{value}" if value.start_with?('//')

    value
  end
end
