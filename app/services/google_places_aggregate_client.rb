require 'json'
require 'net/http'
require 'uri'

class GooglePlacesAggregateClient
  class MissingApiKeyError < StandardError; end
  class RequestError < StandardError; end

  AGGREGATE_URL = 'https://areainsights.googleapis.com/v1:computeInsights'.freeze
  REGION_LOOKUP_URL = GooglePlacesBlackCoffeeClient::BASE_URL
  REGION_LOOKUP_FIELD_MASK = 'places.id,places.name,places.displayName,places.types'.freeze

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

  def count_region_category(region_place:, category:)
    config = GooglePlacesBlackCoffeeClient.config_for(category)
    types = aggregate_types_for(config)
    body = {
      insights: ['INSIGHT_COUNT'],
      filter: {
        locationFilter: {
          region: {
            place: region_place
          }
        },
        typeFilter: {
          includedTypes: types
        },
        operatingStatus: ['OPERATING_STATUS_OPERATIONAL']
      }
    }

    post_json(AGGREGATE_URL, body).fetch('count', 0).to_i
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

    raise RequestError, "No se pudo resolver el Google Place ID de #{region.name}."
  end

  def aggregate_types_for(config)
    types = Array(config[:aggregate_types]).presence ||
            Array(config[:included_type]).presence ||
            Array(config[:google_types]).presence

    raise RequestError, 'La categoria no tiene tipos de Google configurados para conteo.' if types.blank?

    types
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

    parsed = JSON.parse(response.body.presence || '{}')
    return parsed if response.is_a?(Net::HTTPSuccess)

    message = parsed.dig('error', 'message').presence || response.message
    raise RequestError, "Google Places respondio #{response.code}: #{message}"
  rescue JSON::ParserError
    raise RequestError, 'Google Places devolvio una respuesta no JSON.'
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise RequestError, 'Google Places no respondio a tiempo.'
  end
end
