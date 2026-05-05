require 'json'
require 'net/http'
require 'ostruct'
require 'uri'

class GooglePlacesBlackCoffeeClient
  class MissingApiKeyError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = 'https://places.googleapis.com/v1/places:searchText'.freeze
  PLACE_DETAILS_URL = 'https://places.googleapis.com/v1/places'.freeze
  PHOTO_HOST = 'places.googleapis.com'.freeze
  MAX_PAGE_SIZE = 20
  MAX_RESULTS = 60
  MAX_PHOTOS_PER_PLACE = 3
  EXCLUDED_IMPORT_CATEGORIES = %w[concierto festival].freeze
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
    places.editorialSummary
    places.photos
    nextPageToken
  ].join(',').freeze
  PLACE_DETAILS_PHOTO_FIELD_MASK = 'id,photos'.freeze
  PLACE_DETAILS_SYNC_FIELD_MASK = %w[
    id
    name
    displayName
    formattedAddress
    location
    types
    primaryType
    primaryTypeDisplayName
    rating
    userRatingCount
    googleMapsUri
    websiteUri
    nationalPhoneNumber
    addressComponents
    regularOpeningHours
    editorialSummary
    photos
  ].join(',').freeze
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
      subcategory: nil
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
      subcategory: nil
    },
    'cafeteria' => {
      label: 'Cafeterias',
      query: 'cafeterias',
      included_type: 'cafe',
      google_types: %w[cafe],
      aggregate_types: %w[cafe coffee_shop cafeteria],
      subcategory: nil
    },
    'concierto' => {
      label: 'Conciertos',
      query: 'salas de conciertos musica en vivo',
      google_types: %w[event_venue performing_arts_theater],
      aggregate_types: %w[concert_hall event_venue performing_arts_theater auditorium],
      subcategory: nil
    },
    'festival' => {
      label: 'Festivales',
      query: 'festivales eventos',
      google_types: %w[event_venue],
      aggregate_types: %w[event_venue amphitheatre convention_center cultural_center],
      subcategory: nil
    },
    'discoteca' => {
      label: 'Discotecas',
      query: 'discotecas clubs nocturnos',
      included_type: 'night_club',
      google_types: %w[night_club],
      aggregate_types: %w[night_club dance_hall],
      subcategory: nil
    },
    'deportivo' => {
      label: 'Deportivos',
      query: 'planes deportivos centros deportivos',
      included_type: 'gym',
      google_types: %w[gym stadium sports_complex],
      aggregate_types: %w[sports_complex stadium arena gym fitness_center sports_club athletic_field sports_activity_location],
      subcategory: nil
    },
    'escape_room' => {
      label: 'Escape rooms',
      query: 'escape room',
      google_types: %w[amusement_center],
      aggregate_types: %w[amusement_center],
      subcategory: nil
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

  def search(region:, category:, limit:, query_override: nil, location_restriction: nil, append_region_to_query: true, metadata: false)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    normalized_category = category.to_s
    config = BlackCoffeeGoogleImportFilter.enhance_config(normalized_category, self.class.config_for(normalized_category))
    requested_limit = [[limit.to_i, 1].max, MAX_RESULTS].min
    query = build_query(
      region: region,
      config: config,
      query_override: query_override,
      append_region_to_query: append_region_to_query
    )
    places, requests_count, raw_places_count = fetch_places(
      query: query,
      config: config,
      limit: requested_limit,
      location_restriction: location_restriction
    )

    candidates = places.first(requested_limit).map do |place|
      place_to_candidate_attributes(
        place,
        region: region,
        category: normalized_category,
        subcategory: config[:subcategory]
      )
    end

    return { candidates: candidates, requests_count: requests_count, raw_places_count: raw_places_count } if metadata

    candidates
  end

  def photo_urls_from_references(photo_references, max_photos: MAX_PHOTOS_PER_PLACE)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    references = Array(photo_references).first(max_photos)
    image_urls = []
    requests_count = 0

    references.each do |reference|
      photo_name = extract_photo_name(reference)
      next if photo_name.blank?

      payload = get_json(photo_media_uri(photo_name))
      requests_count += 1
      image_url = normalize_photo_uri(payload['photoUri'])
      image_urls << image_url if image_url.present?
    end

    {
      image_urls: image_urls.uniq,
      requests_count: requests_count
    }
  end

  def fetch_place_photo_bundle(place_id:, max_photos: MAX_PHOTOS_PER_PLACE)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    place_resource = normalized_place_resource(place_id)
    payload = get_json(
      URI.parse("#{PLACE_DETAILS_URL}/#{place_resource}"),
      field_mask: PLACE_DETAILS_PHOTO_FIELD_MASK
    )
    photos = Array(payload['photos']).first(max_photos)
    photo_references = photos.map { |photo| photo_reference_payload(photo) }
    photo_result = photo_urls_from_references(photo_references, max_photos: max_photos)

    {
      google_photo_references: photo_references,
      image_urls: photo_result[:image_urls],
      author_attributions: photos.flat_map { |photo| Array(photo['authorAttributions']) },
      raw_photos: photos,
      requests_count: 1 + photo_result[:requests_count]
    }
  end

  def fetch_place_sync_data(place_id:, category:, fallback_city:, fallback_subcategory: nil)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    place_resource = normalized_place_resource(place_id)
    payload = get_json(
      URI.parse("#{PLACE_DETAILS_URL}/#{place_resource}"),
      field_mask: PLACE_DETAILS_SYNC_FIELD_MASK
    )
    attributes = place_to_candidate_attributes(
      payload,
      region: OpenStruct.new(name: fallback_city.to_s.strip.presence || 'Sin ciudad'),
      category: category,
      subcategory: fallback_subcategory
    )
    photos = Array(payload['photos']).first(MAX_PHOTOS_PER_PLACE)

    attributes.merge(
      google_type_tags: BlackCoffeeTaxonomy.google_tags_for_place(payload),
      google_schedule_payload: schedule_payload_for_place(payload),
      requests_count: 1 + photos.count { |photo| photo['name'].present? }
    )
  end

  private

  def build_query(region:, config:, query_override:, append_region_to_query:)
    raw_query = query_override.to_s.strip.presence || config.fetch(:query)
    return raw_query unless append_region_to_query

    "#{raw_query} en #{region.name}, Espana"
  end

  def fetch_places(query:, config:, limit:, location_restriction: nil)
    places = []
    next_page_token = nil
    requests_count = 0
    raw_places_count = 0
    dynamic_filter = config[:dynamic_filter]

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
      body[:strictTypeFiltering] = true if config[:included_type].present?
      body[:locationRestriction] = location_restriction if location_restriction.present?
      body[:pageToken] = next_page_token if next_page_token.present?

      payload = post_json(BASE_URL, body)
      requests_count += 1
      page_places = Array(payload['places'])
      raw_places_count += page_places.size
      page_places = page_places.reject { |place| dynamic_filter.filters_place?(place) } if dynamic_filter&.active_filters?
      places.concat(page_places)
      next_page_token = payload['nextPageToken'].presence
      break if next_page_token.blank? || places.size >= limit
    end

    [places.first(limit), requests_count, raw_places_count]
  end

  def post_json(url, body, field_mask: FIELD_MASK)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-Goog-Api-Key'] = @api_key
    request['X-Goog-FieldMask'] = field_mask
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
      google_description: place.dig('editorialSummary', 'text'),
      google_description_language_code: place.dig('editorialSummary', 'languageCode'),
      image_urls: photos.filter_map { |photo| photo_uri_for(photo['name']) },
      google_photo_references: photos.map { |photo| photo_reference_payload(photo) },
      author_attributions: photos.flat_map { |photo| Array(photo['authorAttributions']) },
      raw_payload: place
    }
  end

  def resolved_subcategory_for(place, category:, fallback:)
    BlackCoffeeTaxonomy.subcategory_for_google_place(
      place,
      category: category,
      fallback: fallback
    )
  end

  def schedule_payload_for_place(place)
    BlackCoffeeImportCandidate.new(raw_payload: place).google_schedule_payload
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

    payload = get_json(photo_media_uri(photo_name))
    normalize_photo_uri(payload['photoUri'])
  rescue RequestError => e
    Rails.logger.warn("Black Coffee Google photo skipped: #{e.message}") if defined?(Rails)
    nil
  end

  def get_json(uri, field_mask: nil)
    request = Net::HTTP::Get.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-Goog-Api-Key'] = @api_key
    request['X-Goog-FieldMask'] = field_mask if field_mask.present?

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
      http.request(request)
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

  def photo_media_uri(photo_name)
    URI::HTTPS.build(
      host: PHOTO_HOST,
      path: "/v1/#{photo_name}/media",
      query: URI.encode_www_form(
        key: @api_key,
        maxWidthPx: 1200,
        skipHttpRedirect: true
      )
    )
  end

  def extract_photo_name(reference)
    return reference if reference.is_a?(String)
    return if !reference.respond_to?(:[])

    reference['name'] || reference[:name]
  end

  def normalized_place_resource(place_id)
    normalized = place_id.to_s.strip
    normalized = normalized.delete_prefix('places/')
    normalized
  end
end
