require 'date'
require 'digest'
require 'uri'

module FanMusicFest
  class Normalizer
    SOURCE = 'fanmusicfest'.freeze
    SPAIN_COUNTRY_NAMES = %w[ES Espana España Spain].freeze
    PORTUGAL_COUNTRY_NAMES = %w[PT Portugal].freeze

    def normalize(raw_payload)
      raw = stringify_hash_or_empty(raw_payload)
      location_nodes = location_nodes(raw['location'])
      location = location_nodes.first || {}
      address = stringify_hash_or_empty(location['address'])
      geo = stringify_hash_or_empty(location['geo'])
      detail = stringify_hash_or_empty(raw['_fanmusicfest_detail'])
      detail_coordinates = stringify_hash_or_empty(detail['coordinates'])
      locations = festival_locations(location_nodes, fallback_coordinates: detail_coordinates)

      source_url = source_url_for(raw)
      organizer_name = clean_text(dig_hash(raw, 'organizer', 'name'))
      edition_title = clean_title(raw['name'])
      display_name = clean_festival_name(organizer_name.presence || edition_title)
      venue_name = clean_location_text(location['name'])
      city = clean_location_text(address['addressLocality'])
      state = clean_location_text(address['addressRegion'])
      country = clean_location_text(address['addressCountry'])
      country_code = country_code_for(country)
      latitude = decimal_or_nil(detail_coordinates['latitude'] || geo['latitude'])
      longitude = decimal_or_nil(detail_coordinates['longitude'] || geo['longitude'])
      coordinates_source = clean_text(detail_coordinates['source']).presence || ('schema_org' if latitude && longitude)
      coordinates_confidence = clean_text(detail_coordinates['confidence']).presence || ('high' if latitude && longitude)
      start_date = parse_date(raw['startDate'])
      end_date = parse_date(raw['endDate'])
      source_description = clean_source_description(detail['source_description'].presence || raw['description'])

      {
        source: SOURCE,
        source_url: source_url,
        source_event_id: source_event_id_for(raw, source_url),
        fingerprint: fingerprint_for(
          source_url: source_url,
          name: display_name,
          city: city,
          state: state,
          start_date: start_date,
          end_date: end_date,
          venue_name: venue_name
        ),
        name: display_name,
        edition_title: edition_title,
        description: nil,
        source_description: source_description,
        source_description_language: source_description.present? ? 'es' : nil,
        source_description_status: source_description.present? ? 'needs_review' : 'not_found',
        address: address_for(location: location, address: address, city: city, state: state, country: country),
        venue_name: venue_name,
        raw_location_text: clean_text(detail['raw_location_text']),
        city: city,
        state: state,
        country: country,
        country_code: country_code,
        latitude: latitude,
        longitude: longitude,
        coordinates_source: coordinates_source,
        coordinates_confidence: coordinates_confidence,
        map_source_url: safe_http_url(detail_coordinates['map_source_url']),
        coordinates_warning: clean_text(detail_coordinates['warning']),
        start_date: start_date,
        end_date: end_date,
        image_url: image_url_for(raw['image']),
        official_url: safe_http_url(detail['official_url']),
        ticket_url: safe_http_url(detail['ticket_url']),
        ticket_price_text: clean_text(detail['ticket_price_text']),
        performers: performer_names(raw['performer']),
        free: raw['isAccessibleForFree'],
        event_status: raw['eventStatus'],
        organizer: stringify_hash(raw['organizer']),
        offers: raw['offers'],
        locations: locations,
        valid: valid?(name: display_name, city: city, country_code: country_code),
        outside_country: country_code.present? && country_code != 'ES',
        raw_payload: raw
      }
    end

    private

    def stringify_hash(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, entry), result| result[key.to_s] = stringify_hash(entry) }
      when Array
        value.map { |entry| stringify_hash(entry) }
      else
        value
      end
    end

    def stringify_hash_or_empty(value)
      normalized = stringify_hash(value)
      normalized.is_a?(Hash) ? normalized : {}
    end

    def location_nodes(value)
      normalized = stringify_hash(value)
      case normalized
      when Array
        normalized.select { |entry| entry.is_a?(Hash) }
      when Hash
        [normalized]
      else
        []
      end
    end

    def clean_location_text(value)
      case value
      when Array
        value.filter_map { |entry| clean_location_text(entry) }.uniq.join(', ').presence
      else
        clean_text(value)
      end
    end

    def festival_locations(nodes, fallback_coordinates:)
      nodes.filter_map.with_index do |location, index|
        address = stringify_hash_or_empty(location['address'])
        geo = stringify_hash_or_empty(location['geo'])
        coordinates = location_coordinates(geo)
        if coordinates.blank? && nodes.one? && fallback_coordinates.present?
          coordinates = location_coordinates(fallback_coordinates, source_key: 'source', confidence_key: 'confidence')
        end

        entry = {
          'name' => clean_location_text(location['name']),
          'city' => clean_location_text(address['addressLocality']),
          'province' => clean_location_text(address['addressRegion']),
          'country' => clean_location_text(address['addressCountry']),
          'coordinates' => coordinates&.slice('latitude', 'longitude'),
          'coordinatesSource' => coordinates&.[]('source'),
          'coordinatesConfidence' => coordinates&.[]('confidence')
        }.compact
        entry['position'] = index if entry.present?
        entry.presence
      end.uniq { |entry| [entry['name'], entry['city'], entry['province'], entry.dig('coordinates', 'latitude'), entry.dig('coordinates', 'longitude')] }
    end

    def location_coordinates(payload, source_key: 'source', confidence_key: 'confidence')
      latitude = decimal_or_nil(payload['latitude'])
      longitude = decimal_or_nil(payload['longitude'])
      return nil if latitude.blank? || longitude.blank?

      {
        'latitude' => latitude,
        'longitude' => longitude,
        'source' => clean_text(payload[source_key]).presence || 'schema_org',
        'confidence' => clean_text(payload[confidence_key]).presence || 'high'
      }
    end

    def dig_hash(hash, *keys)
      keys.reduce(hash) do |memo, key|
        return nil unless memo.is_a?(Hash)

        memo[key.to_s]
      end
    end

    def clean_text(value)
      ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
    end

    def clean_title(value)
      clean_text(value).to_s.split('|').first.to_s.squish.presence
    end

    def clean_festival_name(value)
      clean_text(value).to_s.sub(/\s+\d{4}\z/, '').squish.presence
    end

    def clean_source_description(value)
      text = clean_text(value)
      return nil if text.blank? || text.length < 40

      text.first(2_000)
    end

    def source_url_for(raw)
      candidate = raw['url'].presence || raw['@id'].to_s.sub(/#event\z/, '').presence
      uri = URI.parse(candidate.to_s)
      host = uri.host.to_s.downcase
      return nil unless uri.scheme == 'https' && %w[fanmusicfest.com www.fanmusicfest.com].include?(host)

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def source_event_id_for(raw, source_url)
      raw['@id'].presence || source_url
    end

    def country_code_for(country)
      return nil if country.blank?
      return 'ES' if SPAIN_COUNTRY_NAMES.include?(country)
      return 'PT' if PORTUGAL_COUNTRY_NAMES.include?(country)

      country.to_s.upcase if country.to_s.length == 2
    end

    def decimal_or_nil(value)
      return nil if value.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def address_for(location:, address:, city:, state:, country:)
      street = clean_text(address['streetAddress'])
      location_name = clean_text(location['name'])
      [street, location_name, city, state, country].compact.reject(&:blank?).join(', ').presence || city || location_name || 'Direccion pendiente de revisar'
    end

    def image_url_for(image)
      case image
      when Hash
        clean_text(image['url'])
      when Array
        image.map { |entry| image_url_for(entry) }.find(&:present?)
      else
        clean_text(image)
      end
    end

    def performer_names(value)
      Array(value).filter_map do |entry|
        entry.is_a?(Hash) ? clean_text(entry['name'] || entry[:name]) : clean_text(entry)
      end.uniq
    end

    def safe_http_url(value)
      uri = URI.parse(value.to_s)
      return nil unless %w[http https].include?(uri.scheme) && uri.host.present?

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def valid?(name:, city:, country_code:)
      name.present? && city.present? && country_code == 'ES'
    end

    def fingerprint_for(source_url:, name:, city:, state:, start_date:, end_date:, venue_name:)
      components = [source_url, name, city, state, start_date, end_date, venue_name]
      Digest::SHA256.hexdigest(components.compact.join('|'))[0, 32]
    end
  end
end
