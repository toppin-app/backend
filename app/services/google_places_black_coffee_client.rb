require 'json'
require 'net/http'
require 'ostruct'
require 'set'
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
  DRY_RUN_FIELD_MASK = %w[
    places.id
    places.name
    places.displayName
    places.formattedAddress
    places.location
    places.types
    places.primaryType
    places.primaryTypeDisplayName
    places.addressComponents
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

  def self.max_photos_per_place
    value = ENV.fetch('BLACK_COFFEE_MAX_PHOTOS_PER_PLACE', MAX_PHOTOS_PER_PLACE).to_i
    [[value, 0].max, 10].min
  end

  def self.allow_google_photo_url_resolution?
    # Google photoUri values are temporary; keep media requests behind an explicit cost gate.
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BLACK_COFFEE_ALLOW_GOOGLE_PHOTO_URL_RESOLUTION', 'false'))
  end

  def self.resolve_photo_urls_during_import?
    return false unless allow_google_photo_url_resolution?

    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BLACK_COFFEE_RESOLVE_PHOTO_URLS_DURING_IMPORT', 'false'))
  end

  def self.skip_existing_places?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BLACK_COFFEE_SKIP_EXISTING_PLACES', 'true'))
  end

  def self.skip_imported_candidates?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BLACK_COFFEE_SKIP_IMPORTED_CANDIDATES', 'true'))
  end

  def self.strict_region_filter?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BLACK_COFFEE_STRICT_REGION_FILTER', 'true'))
  end

  def self.require_photos_during_import?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BLACK_COFFEE_REQUIRE_PHOTOS_DURING_IMPORT', 'true'))
  end

  def self.import_options_payload
    {
      max_photos_per_place: max_photos_per_place,
      allow_google_photo_url_resolution: allow_google_photo_url_resolution?,
      resolve_photo_urls_during_import: resolve_photo_urls_during_import?,
      skip_existing_places: skip_existing_places?,
      skip_imported_candidates: skip_imported_candidates?,
      strict_region_filter: strict_region_filter?,
      require_photos_during_import: require_photos_during_import?
    }
  end

  # Google photo names are only kept as short-lived review metadata. Importing
  # avoids Place Photos calls; explicit image refresh can fall back to Details
  # to obtain fresh photo names if the stored ones have expired.

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
    @photo_uri_cache = {}
  end

  def search(
    region:,
    category:,
    limit:,
    query_override: nil,
    location_restriction: nil,
    append_region_to_query: true,
    metadata: false,
    max_photos_per_place: self.class.max_photos_per_place,
    resolve_photo_urls_during_import: self.class.resolve_photo_urls_during_import?,
    skip_existing_places: self.class.skip_existing_places?,
    skip_imported_candidates: self.class.skip_imported_candidates?,
    strict_region_filter: self.class.strict_region_filter?,
    require_photos_during_import: self.class.require_photos_during_import?,
    search_field_mask: FIELD_MASK
  )
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    normalized_category = category.to_s
    config = BlackCoffeeGoogleImportFilter.enhance_config(normalized_category, self.class.config_for(normalized_category))
    requested_limit = [[limit.to_i, 1].max, MAX_RESULTS].min
    import_options = {
      max_photos_per_place: max_photos_per_place,
      resolve_photo_urls_during_import: resolve_photo_urls_during_import,
      skip_existing_places: skip_existing_places,
      skip_imported_candidates: skip_imported_candidates,
      strict_region_filter: strict_region_filter,
      require_photos_during_import: require_photos_during_import
    }
    query = build_query(
      region: region,
      config: config,
      query_override: query_override,
      append_region_to_query: append_region_to_query
    )
    places, requests_count, raw_places_count, filter_stats = fetch_places(
      query: query,
      config: config,
      limit: requested_limit,
      location_restriction: location_restriction,
      field_mask: search_field_mask
    )

    stats = empty_import_stats(
      raw_candidates_count: raw_places_count,
      search_requests_count: requests_count,
      invalid_category_skipped_count: filter_stats[:invalid_category_skipped]
    )
    existing_place_ids = skip_existing_places ? existing_venue_place_ids(places) : Set.new
    imported_candidate_place_ids = skip_imported_candidates ? existing_import_candidate_place_ids(places) : Set.new

    candidates = []
    places.each do |place|
      place_id = place_id_for(place)
      if place_id.present? && existing_place_ids.include?(place_id)
        stats[:already_existing_skipped] += 1
        next
      end

      if place_id.present? && imported_candidate_place_ids.include?(place_id)
        stats[:already_imported_skipped] += 1
        next
      end

      region_validation = GooglePlacesRegionValidator.validate(
        place,
        region: region,
        strict: strict_region_filter
      )
      unless region_validation.valid?
        stats[:outside_region_skipped] += 1
        next
      end

      if require_photos_during_import && Array(place['photos']).blank?
        stats[:no_photo_skipped] += 1
        next
      end

      candidates << place_to_candidate_attributes(
        place,
        region: region,
        category: normalized_category,
        subcategory: config[:subcategory],
        max_photos: max_photos_per_place,
        resolve_photo_urls: resolve_photo_urls_during_import,
        metrics: stats
      )
      break if candidates.size >= requested_limit
    end

    log_import_summary(
      region: region,
      category: normalized_category,
      query: query,
      stats: stats,
      valid_candidates_count: candidates.size,
      import_options: import_options
    )

    return search_metadata_payload(candidates, stats, import_options: import_options) if metadata

    candidates
  end

  def photo_urls_from_references(photo_references, max_photos: self.class.max_photos_per_place)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?
    return empty_photo_url_result unless self.class.allow_google_photo_url_resolution?

    photo_names = Array(photo_references)
      .filter_map { |reference| extract_photo_name(reference).to_s.strip.presence }
      .uniq
      .first(max_photos)
    image_urls = []
    requests_count = 0

    photo_names.each do |photo_name|
      requested = !photo_uri_cached?(photo_name)
      image_url = photo_uri_for_with_cache(photo_name)
      requests_count += 1 if requested
      image_urls << image_url if image_url.present?
    end

    {
      image_urls: image_urls.uniq,
      requests_count: requests_count
    }
  end

  def fetch_place_photo_bundle(place_id:, max_photos: self.class.max_photos_per_place)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?
    return empty_photo_bundle unless self.class.allow_google_photo_url_resolution?

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
    photo_metrics = {
      google_requests: { photos: 0 },
      photos: { references_saved: 0, urls_resolved: 0 }
    }
    attributes = place_to_candidate_attributes(
      payload,
      region: OpenStruct.new(name: fallback_city.to_s.strip.presence || 'Sin ciudad'),
      category: category,
      subcategory: fallback_subcategory,
      max_photos: self.class.max_photos_per_place,
      resolve_photo_urls: true,
      metrics: photo_metrics
    )

    attributes.merge(
      google_type_tags: BlackCoffeeTaxonomy.google_tags_for_place(payload),
      google_primary_type: BlackCoffeeTaxonomy.google_primary_type_for_place(payload),
      google_secondary_type_tags: BlackCoffeeTaxonomy.google_secondary_tags_for_place(payload),
      google_schedule_payload: schedule_payload_for_place(payload),
      requests_count: 1 + photo_metrics.dig(:google_requests, :photos).to_i
    )
  end

  private

  def empty_photo_url_result
    {
      image_urls: [],
      requests_count: 0
    }
  end

  def empty_photo_bundle
    {
      google_photo_references: [],
      image_urls: [],
      author_attributions: [],
      raw_photos: [],
      requests_count: 0
    }
  end

  def build_query(region:, config:, query_override:, append_region_to_query:)
    raw_query = query_override.to_s.strip.presence || config.fetch(:query)
    return raw_query unless append_region_to_query

    "#{raw_query} en #{region.name}, Espana"
  end

  def fetch_places(query:, config:, limit:, location_restriction: nil, field_mask: FIELD_MASK)
    places = []
    next_page_token = nil
    requests_count = 0
    raw_places_count = 0
    filter_stats = { invalid_category_skipped: 0 }
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

      payload = post_json(BASE_URL, body, field_mask: field_mask)
      requests_count += 1
      page_places = Array(payload['places'])
      raw_places_count += page_places.size
      if dynamic_filter&.active_filters?
        before_dynamic_filter_count = page_places.size
        page_places = page_places.reject { |place| dynamic_filter.filters_place?(place) }
        filter_stats[:invalid_category_skipped] += before_dynamic_filter_count - page_places.size
      end
      places.concat(page_places)
      next_page_token = payload['nextPageToken'].presence
      break if next_page_token.blank? || places.size >= limit
    end

    [places.first(limit), requests_count, raw_places_count, filter_stats]
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

  def place_to_candidate_attributes(place, region:, category:, subcategory:, max_photos: self.class.max_photos_per_place, resolve_photo_urls: true, metrics: nil)
    photos = Array(place['photos'])
      .uniq { |photo| photo['name'].to_s }
      .first(max_photos.to_i)
    address_components = place['addressComponents']
    photo_references = photos.map { |photo| photo_reference_payload(photo) }
    metrics[:photos][:references_saved] += photo_references.size if metrics
    image_urls = []

    if resolve_photo_urls && self.class.allow_google_photo_url_resolution?
      photos.each do |photo|
        photo_name = photo['name']
        next if photo_name.blank?

        requested = !photo_uri_cached?(photo_name)
        image_url = photo_uri_for(photo_name)
        metrics[:google_requests][:photos] += 1 if metrics && requested
        image_urls << image_url if image_url.present?
      end
      metrics[:photos][:urls_resolved] += image_urls.size if metrics
    end

    {
      google_place_id: place_id_for(place),
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
      image_urls: image_urls.uniq,
      google_photo_references: photo_references,
      author_attributions: photos.flat_map { |photo| Array(photo['authorAttributions']) },
      raw_payload: place
    }
  end

  def place_id_for(place)
    place['id'].presence || place['name'].to_s.split('/').last.presence
  end

  def existing_venue_place_ids(places)
    place_ids = Array(places).map { |place| place_id_for(place).to_s.strip.presence }.compact.uniq
    return Set.new if place_ids.blank? || !Venue.column_names.include?('google_place_id')

    Set.new(Venue.where(google_place_id: place_ids).pluck(:google_place_id))
  end

  def existing_import_candidate_place_ids(places)
    place_ids = Array(places).map { |place| place_id_for(place).to_s.strip.presence }.compact.uniq
    return Set.new if place_ids.blank?
    return Set.new unless ActiveRecord::Base.connection.data_source_exists?('black_coffee_import_candidates')
    return Set.new unless BlackCoffeeImportCandidate.column_names.include?('google_place_id')

    reusable_statuses = BlackCoffeeImportCandidate::STATUSES - ['rejected']
    Set.new(
      BlackCoffeeImportCandidate
        .where(google_place_id: place_ids, status: reusable_statuses)
        .pluck(:google_place_id)
    )
  rescue ActiveRecord::ActiveRecordError
    Set.new
  end

  def empty_import_stats(raw_candidates_count:, search_requests_count:, invalid_category_skipped_count:)
    {
      raw_candidates_count: raw_candidates_count.to_i,
      already_existing_skipped: 0,
      already_imported_skipped: 0,
      outside_region_skipped: 0,
      no_photo_skipped: 0,
      invalid_category_skipped: invalid_category_skipped_count.to_i,
      google_requests: {
        search: search_requests_count.to_i,
        details: 0,
        photos: 0
      },
      photos: {
        references_saved: 0,
        urls_resolved: 0
      }
    }
  end

  def search_metadata_payload(candidates, stats, import_options:)
    {
      candidates: candidates,
      requests_count: stats.dig(:google_requests, :search).to_i +
        stats.dig(:google_requests, :details).to_i +
        stats.dig(:google_requests, :photos).to_i,
      raw_places_count: stats[:raw_candidates_count].to_i,
      raw_candidates_count: stats[:raw_candidates_count].to_i,
      already_existing_skipped: stats[:already_existing_skipped].to_i,
      already_imported_skipped: stats[:already_imported_skipped].to_i,
      outside_region_skipped: stats[:outside_region_skipped].to_i,
      no_photo_skipped: stats[:no_photo_skipped].to_i,
      invalid_category_skipped: stats[:invalid_category_skipped].to_i,
      new_places_created: candidates.size,
      google_requests: stats[:google_requests],
      photos: stats[:photos],
      import_options: import_options
    }
  end

  def log_import_summary(region:, category:, query:, stats:, valid_candidates_count:, import_options:)
    return unless defined?(Rails)

    Rails.logger.info(
      {
        event: 'black_coffee_google_import_search_summary',
        region: region.respond_to?(:name) ? region.name : region.to_s,
        category: category,
        query: query,
        candidates_found: stats[:raw_candidates_count],
        valid_candidates: valid_candidates_count,
        already_existing_skipped: stats[:already_existing_skipped],
        already_imported_skipped: stats[:already_imported_skipped],
        outside_region_skipped: stats[:outside_region_skipped],
        no_photo_skipped: stats[:no_photo_skipped],
        invalid_category_skipped: stats[:invalid_category_skipped],
        google_requests: stats[:google_requests],
        photos: stats[:photos],
        import_options: import_options
      }.to_json
    )
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
    photo_uri_for_with_cache(photo_name)
  rescue RequestError => e
    Rails.logger.warn("Black Coffee Google photo skipped: #{e.message}") if defined?(Rails)
    nil
  end

  def photo_uri_for_with_cache(photo_name)
    normalized_photo_name = photo_name.to_s.strip
    return if normalized_photo_name.blank?
    return @photo_uri_cache[normalized_photo_name] if @photo_uri_cache.key?(normalized_photo_name)

    payload = get_json(photo_media_uri(normalized_photo_name))
    @photo_uri_cache[normalized_photo_name] = normalize_photo_uri(payload['photoUri'])
  end

  def photo_uri_cached?(photo_name)
    @photo_uri_cache.key?(photo_name.to_s.strip)
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
