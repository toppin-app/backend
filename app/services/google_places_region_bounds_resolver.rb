require 'json'
require 'net/http'
require 'uri'

class GooglePlacesRegionBoundsResolver
  REGION_FIELD_MASK = 'places.id,places.name,places.displayName,places.viewport'.freeze

  def initialize(api_key: GooglePlacesBlackCoffeeClient.api_key)
    @api_key = api_key
  end

  def resolve(region)
    raise GooglePlacesBlackCoffeeClient::MissingApiKeyError, 'Falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY en el entorno del servidor.' if @api_key.blank?

    viewport_bounds = viewport_bounds_for(region)
    return viewport_bounds if viewport_bounds.present?

    fallback_bounds_for(region)
  end

  private

  def viewport_bounds_for(region)
    body = {
      textQuery: "#{region.name}, Espana",
      languageCode: 'es',
      regionCode: 'ES',
      includedType: 'administrative_area_level_1',
      pageSize: 1
    }
    payload = post_json(GooglePlacesBlackCoffeeClient::BASE_URL, body, field_mask: REGION_FIELD_MASK)
    viewport = Array(payload['places']).first&.dig('viewport')
    bounds = normalize_viewport(viewport)
    return if bounds.blank?

    bounds.merge(strategy: 'viewport')
  rescue GooglePlacesBlackCoffeeClient::RequestError
    nil
  end

  def fallback_bounds_for(region)
    circle = GooglePlacesAggregateClient::FALLBACK_REGION_CIRCLES[region.slug.to_s]
    raise GooglePlacesBlackCoffeeClient::RequestError, "No se pudo resolver una geometria util para #{region.name}." if circle.blank?

    latitude = circle.fetch(:latitude).to_f
    longitude = circle.fetch(:longitude).to_f
    radius_meters = circle.fetch(:radius).to_f
    lat_delta = radius_meters / 111_320.0
    lng_denominator = 111_320.0 * [Math.cos(latitude * Math::PI / 180.0).abs, 0.15].max
    lng_delta = radius_meters / lng_denominator

    {
      low: {
        latitude: latitude - lat_delta,
        longitude: longitude - lng_delta
      },
      high: {
        latitude: latitude + lat_delta,
        longitude: longitude + lng_delta
      },
      strategy: 'circle'
    }
  end

  def normalize_viewport(viewport)
    low = viewport&.dig('low')
    high = viewport&.dig('high')
    return if low.blank? || high.blank?

    low_lat = low['latitude'].to_f
    low_lng = low['longitude'].to_f
    high_lat = high['latitude'].to_f
    high_lng = high['longitude'].to_f
    return if high_lat <= low_lat || high_lng <= low_lng

    {
      low: {
        latitude: low_lat,
        longitude: low_lng
      },
      high: {
        latitude: high_lat,
        longitude: high_lng
      }
    }
  end

  def post_json(url, body, field_mask:)
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
    raise GooglePlacesBlackCoffeeClient::RequestError, "Google Places respondio #{response.code}: #{message}"
  rescue JSON::ParserError
    raise GooglePlacesBlackCoffeeClient::RequestError, 'Google Places devolvio una respuesta no JSON.'
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise GooglePlacesBlackCoffeeClient::RequestError, 'Google Places no respondio a tiempo.'
  end
end
