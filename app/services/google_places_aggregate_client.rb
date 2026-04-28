require 'json'
require 'net/http'
require 'uri'

class GooglePlacesAggregateClient
  class MissingApiKeyError < StandardError; end
  class RequestError < StandardError
    attr_reader :details

    def initialize(message, details: nil)
      @details = details.to_s.strip.present? ? details : message
      super(message)
    end
  end

  AGGREGATE_URL = 'https://areainsights.googleapis.com/v1:computeInsights'.freeze
  REGION_LOOKUP_URL = GooglePlacesBlackCoffeeClient::BASE_URL
  REGION_LOOKUP_FIELD_MASK = 'places.id,places.name,places.displayName,places.types'.freeze
  FALLBACK_REGION_CIRCLES = {
    'andalucia' => { latitude: 37.5443, longitude: -4.7278, radius: 260_000 },
    'aragon' => { latitude: 41.5976, longitude: -0.9057, radius: 180_000 },
    'asturias' => { latitude: 43.3614, longitude: -5.8593, radius: 80_000 },
    'islas_baleares' => { latitude: 39.5342, longitude: 2.8577, radius: 170_000 },
    'canarias' => { latitude: 28.2916, longitude: -16.6291, radius: 260_000 },
    'cantabria' => { latitude: 43.1828, longitude: -3.9878, radius: 75_000 },
    'castilla_la_mancha' => { latitude: 39.2796, longitude: -3.0977, radius: 260_000 },
    'castilla_y_leon' => { latitude: 41.6523, longitude: -4.7245, radius: 285_000 },
    'cataluna' => { latitude: 41.5912, longitude: 1.5209, radius: 170_000 },
    'comunidad_valenciana' => { latitude: 39.4840, longitude: -0.7530, radius: 180_000 },
    'extremadura' => { latitude: 39.4937, longitude: -6.0679, radius: 190_000 },
    'galicia' => { latitude: 42.5751, longitude: -8.1339, radius: 160_000 },
    'comunidad_de_madrid' => { latitude: 40.4168, longitude: -3.7038, radius: 90_000 },
    'region_de_murcia' => { latitude: 37.9922, longitude: -1.1307, radius: 85_000 },
    'navarra' => { latitude: 42.6954, longitude: -1.6761, radius: 80_000 },
    'pais_vasco' => { latitude: 43.0000, longitude: -2.6000, radius: 85_000 },
    'la_rioja' => { latitude: 42.2871, longitude: -2.5396, radius: 60_000 },
    'ceuta' => { latitude: 35.8894, longitude: -5.3213, radius: 7_000 },
    'melilla' => { latitude: 35.2923, longitude: -2.9381, radius: 8_000 }
  }.freeze

  def self.api_key
    GooglePlacesBlackCoffeeClient.api_key
  end

  def initialize(api_key: self.class.api_key)
    @api_key = api_key
  end

  def region_place_resource_name(region)
    raise MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    existing = normalize_region_place_id(region.google_region_place_id) if region.respond_to?(:google_region_place_id)
    return [existing, false] if existing.present?

    resolved = resolve_region_place_resource_name(region)
    if region.has_attribute?(:google_region_place_id)
      region.update!(
        google_region_place_id: resolved.delete_prefix('places/'),
        google_region_place_id_resolved_at: Time.current
      )
    end

    [resolved, true]
  end

  def count_region_category(region:, region_place:, category:)
    config = GooglePlacesBlackCoffeeClient.config_for(category)
    types = aggregate_types_for(config)
    body = {
      insights: ['INSIGHT_COUNT'],
      filter: {
        locationFilter: location_filter_for(region: region, region_place: region_place),
        typeFilter: {
          includedTypes: types
        },
        operatingStatus: ['OPERATING_STATUS_OPERATIONAL']
      }
    }

    post_json(AGGREGATE_URL, body).fetch('count', 0).to_i
  end

  def circle_fallback_enabled?(region)
    region.respond_to?(:has_attribute?) &&
      region.has_attribute?(:google_count_location_strategy) &&
      region.google_count_location_strategy == 'circle'
  end

  def circle_fallback_available?(region)
    FALLBACK_REGION_CIRCLES.key?(region.slug.to_s)
  end

  def enable_circle_fallback!(region, reason)
    return unless region.respond_to?(:has_attribute?) && region.has_attribute?(:google_count_location_strategy)

    attributes = { google_count_location_strategy: 'circle' }
    if region.has_attribute?(:google_count_location_note)
      attributes[:google_count_location_note] = "Google region fallback: #{reason.message}"
    end
    region.update!(attributes)
  end

  def unsupported_region_geometry_error?(error)
    error.message.match?(/well defined geometry|unsupported region|location.*not supported/i) ||
      error.details.to_s.match?(/well defined geometry|unsupported region|location.*not supported/i)
  end

  private

  def resolve_region_place_resource_name(region)
    body = {
      textQuery: "#{region.name}, Espana",
      languageCode: 'es',
      regionCode: 'ES',
      includedType: 'administrative_area_level_1',
      pageSize: 1
    }
    payload = post_json(REGION_LOOKUP_URL, body, field_mask: REGION_LOOKUP_FIELD_MASK)
    place = Array(payload['places']).first
    resource_name = place&.fetch('name', nil).presence || normalize_region_place_id(place&.fetch('id', nil))

    return resource_name if resource_name.present?

    raise RequestError.new(
      "No se pudo resolver el Google Place ID de #{region.name}.",
      details: JSON.pretty_generate(
        error: 'region_place_id_not_found',
        region: {
          id: region.id,
          name: region.name,
          slug: region.slug,
          country_code: region.country_code
        },
        query: body,
        google_response: payload
      )
    )
  end

  def aggregate_types_for(config)
    types = Array(config[:aggregate_types]).presence ||
            Array(config[:included_type]).presence ||
            Array(config[:google_types]).presence

    if types.blank?
      raise RequestError.new(
        'La categoria no tiene tipos de Google configurados para conteo.',
        details: JSON.pretty_generate(error: 'missing_aggregate_types', config: config)
      )
    end

    types
  end

  def location_filter_for(region:, region_place:)
    return circle_location_filter(region) if circle_fallback_enabled?(region)

    {
      region: {
        place: region_place
      }
    }
  end

  def circle_location_filter(region)
    circle = FALLBACK_REGION_CIRCLES[region.slug.to_s]
    if circle.blank?
      raise RequestError.new(
        "No hay circulo de fallback configurado para #{region.name}.",
        details: JSON.pretty_generate(error: 'missing_circle_fallback', region: { id: region.id, name: region.name, slug: region.slug })
      )
    end

    {
      circle: {
        latLng: {
          latitude: circle.fetch(:latitude),
          longitude: circle.fetch(:longitude)
        },
        radius: circle.fetch(:radius)
      }
    }
  end

  def normalize_region_place_id(value)
    normalized = value.to_s.strip
    return if normalized.blank?

    normalized.start_with?('places/') ? normalized : "places/#{normalized}"
  end

  def post_json(url, body, field_mask: nil)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-Goog-Api-Key'] = @api_key
    request['X-Goog-FieldMask'] = field_mask if field_mask.present?
    request.body = JSON.generate(body)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 30, open_timeout: 10) do |http|
      http.request(request)
    end

    parsed, parse_error = parse_json_response(response.body)
    if response.is_a?(Net::HTTPSuccess)
      return parsed if parse_error.blank?

      raise RequestError.new(
        'Google Places devolvio una respuesta no JSON.',
        details: request_error_details(url: url, body: body, field_mask: field_mask, response: response, parse_error: parse_error)
      )
    end

    message = parsed&.dig('error', 'message').presence || response.message
    raise RequestError.new(
      "Google Places respondio #{response.code}: #{message}",
      details: request_error_details(url: url, body: body, field_mask: field_mask, response: response, parsed: parsed, parse_error: parse_error)
    )
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise RequestError.new(
      'Google Places no respondio a tiempo.',
      details: JSON.pretty_generate(
        error: 'timeout',
        url: url,
        request_body: body,
        field_mask: field_mask
      )
    )
  end

  def parse_json_response(raw_body)
    [JSON.parse(raw_body.presence || '{}'), nil]
  rescue JSON::ParserError => e
    [{}, e.message]
  end

  def request_error_details(url:, body:, field_mask:, response:, parsed: nil, parse_error: nil)
    JSON.pretty_generate(
      error_context: {
        service: url == AGGREGATE_URL ? 'Places Aggregate API' : 'Places API Text Search',
        endpoint: url,
        http_method: 'POST',
        field_mask: field_mask,
        request_body: body
      },
      google_response: {
        http_status: response.code,
        http_message: response.message,
        parsed_error: parsed&.dig('error'),
        parse_error: parse_error,
        raw_body: response.body.to_s
      },
      diagnostic_hints: diagnostic_hints(parsed&.dig('error', 'message').presence || response.body.to_s)
    )
  end

  def diagnostic_hints(message)
    normalized = message.to_s
    hints = []
    hints << 'Verifica que Places Aggregate API este habilitada en el mismo proyecto de la API key.' if normalized.match?(/not been used|disabled|SERVICE_DISABLED/i)
    hints << 'Verifica billing del proyecto en Google Cloud.' if normalized.match?(/billing/i)
    hints << 'La API key tiene restricciones de APIs y no permite areainsights.googleapis.com. Agrega Places Aggregate API a las APIs permitidas de esa key.' if normalized.match?(/API_KEY_SERVICE_BLOCKED|areainsights\.googleapis\.com.*blocked|ComputeInsights.*blocked/i)
    hints << 'Verifica restricciones de la API key: IPs, HTTP referrers y APIs permitidas.' if normalized.match?(/API key|not authorized|PERMISSION_DENIED/i)
    hints << 'La region de Google puede no estar soportada como polygon/region; prueba otra comunidad o revisa el Place ID regional.' if normalized.match?(/region.*not supported|location.*not supported|unsupported region/i)
    hints.presence || ['Revisa http_status, parsed_error y request_body para diagnosticar el fallo exacto.']
  end
end
