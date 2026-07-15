require 'date'
require 'digest'
require 'uri'

module SongkickConcerts
  class Normalizer
    SOURCE = 'songkick'.freeze
    SPAIN_COUNTRY_NAMES = %w[ES Espana España Spain].freeze
    COUNTRY_CODE_ALIASES = {
      'portugal' => 'PT',
      'france' => 'FR',
      'francia' => 'FR',
      'italy' => 'IT',
      'italia' => 'IT',
      'germany' => 'DE',
      'alemania' => 'DE',
      'united kingdom' => 'GB',
      'uk' => 'GB'
    }.freeze

    def normalize(raw_payload)
      raw = stringify_hash_or_empty(raw_payload)
      location = location_node(raw['location'])
      address = stringify_hash_or_empty(location['address'])
      geo = stringify_hash_or_empty(location['geo'])
      source_url = source_url_for(raw)
      performers = performer_names(raw['performer'])
      raw_title = clean_text(raw['name'])
      display_name = display_name_for(raw_title, performers)
      venue_name = clean_location_text(location['name'])
      city = clean_location_text(address['addressLocality'])
      state = clean_location_text(address['addressRegion'])
      country = clean_location_text(address['addressCountry'])
      country_code = country_code_for(country)
      latitude = decimal_or_nil(geo['latitude'])
      longitude = decimal_or_nil(geo['longitude'])
      start_at = parse_time(raw['startDate'])
      end_at = parse_time(raw['endDate'])
      start_date = parse_date(raw['startDate'])
      end_date = parse_date(raw['endDate'])
      image_url = image_url_for(raw['image'])
      event_id = source_event_id_for(raw, source_url)
      source_description = source_description_for(raw)
      event_dedupe_key = event_dedupe_key_for(
        name: display_name,
        city: city,
        venue_name: venue_name,
        start_at: start_at,
        start_date: start_date
      )

      {
        source: SOURCE,
        source_url: source_url,
        source_event_id: event_id,
        event_dedupe_key: event_dedupe_key,
        fingerprint: fingerprint_for(
          source_url: source_url,
          source_event_id: event_id,
          name: display_name,
          city: city,
          venue_name: venue_name,
          start_date: start_date
        ),
        name: display_name,
        edition_title: raw_title,
        address: address_for(location: location, address: address, city: city, state: state, country: country),
        venue_name: venue_name,
        city: city,
        state: state,
        country: country,
        country_code: country_code,
        latitude: latitude,
        longitude: longitude,
        coordinates_source: latitude && longitude ? 'schema_org' : nil,
        coordinates_confidence: latitude && longitude ? 'high' : nil,
        start_at: start_at,
        end_at: end_at,
        start_date: start_date,
        end_date: end_date,
        image_url: image_url,
        source_description: source_description,
        source_description_language: 'en',
        source_description_status: source_description.present? ? 'needs_review' : 'not_found',
        ticket_url: offer_url(raw['offers']),
        official_url: source_url,
        performers: performers,
        genres: genres_for(raw['performer']),
        event_status: raw['eventStatus'],
        offers: raw['offers'],
        locations: [location_summary(location, address, latitude, longitude)].compact,
        non_concert_like: non_concert_like?(source_url, raw_title),
        valid: valid?(name: display_name, city: city, country_code: country_code),
        outside_country: country.present? && country_code != 'ES',
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

    def location_node(value)
      normalized = stringify_hash(value)
      case normalized
      when Array
        normalized.find { |entry| entry.is_a?(Hash) } || {}
      when Hash
        normalized
      else
        {}
      end
    end

    def clean_text(value)
      ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
    end

    def clean_location_text(value)
      case value
      when Array
        value.filter_map { |entry| clean_location_text(entry) }.uniq.join(', ').presence
      else
        clean_text(value)
      end
    end

    def display_name_for(raw_title, performers)
      return performers.first(3).join(' + ') if performers.any?

      clean_text(raw_title.to_s.split(/\s+@\s+/).first) || raw_title
    end

    def source_description_for(raw)
      text = clean_text(raw['description'])
      return nil if text.blank? || text.length < 20

      text.first(1_000)
    end

    def source_url_for(raw)
      candidate = raw['url'].presence || raw['@id'].to_s.sub(/#event\z/, '').presence
      uri = URI.parse(candidate.to_s)
      host = uri.host.to_s.downcase
      return nil unless uri.scheme == 'https' && %w[songkick.com www.songkick.com].include?(host)

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def source_event_id_for(raw, source_url)
      event_id_from_url(source_url).presence ||
        raw['@id'].to_s.sub(/#event\z/, '').presence ||
        source_url
    end

    def event_id_from_url(source_url)
      uri = URI.parse(source_url.to_s)
      match = uri.path.match(%r{/(?:concerts|events|id)/(\d+)})
      match&.captures&.first
    rescue URI::InvalidURIError
      nil
    end

    def country_code_for(country)
      return nil if country.blank?

      normalized_country = country.to_s.strip
      return 'ES' if SPAIN_COUNTRY_NAMES.any? { |name| name.downcase == normalized_country.downcase }
      return COUNTRY_CODE_ALIASES[normalized_country.downcase] if COUNTRY_CODE_ALIASES.key?(normalized_country.downcase)

      normalized_country.upcase if normalized_country.length == 2
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

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
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
      array_wrap(value).filter_map do |entry|
        entry.is_a?(Hash) ? clean_text(entry['name'] || entry[:name]) : clean_text(entry)
      end.uniq
    end

    def genres_for(value)
      array_wrap(value).flat_map do |entry|
        next [] unless entry.is_a?(Hash)

        array_wrap(entry['genre']).filter_map { |genre| clean_text(genre) }
      end.uniq
    end

    def offer_url(value)
      array_wrap(value).filter_map do |entry|
        entry = stringify_hash_or_empty(entry)
        safe_http_url(entry['url'])
      end.first
    end

    def safe_http_url(value)
      uri = URI.parse(value.to_s)
      return nil unless %w[http https].include?(uri.scheme) && uri.host.present?

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def array_wrap(value)
      case value
      when nil
        []
      when Array
        value
      else
        [value]
      end
    end

    def location_summary(location, address, latitude, longitude)
      summary = {
        'name' => clean_location_text(location['name']),
        'city' => clean_location_text(address['addressLocality']),
        'province' => clean_location_text(address['addressRegion']),
        'country' => clean_location_text(address['addressCountry'])
      }.compact
      if latitude.present? && longitude.present?
        summary['coordinates'] = {
          'latitude' => latitude,
          'longitude' => longitude
        }
        summary['coordinatesSource'] = 'schema_org'
        summary['coordinatesConfidence'] = 'high'
      end
      summary.presence
    end

    def non_concert_like?(source_url, raw_title)
      path = URI.parse(source_url.to_s).path
      path.include?('/festivals/') || raw_title.to_s.match?(/\bfestival\b/i)
    rescue URI::InvalidURIError
      raw_title.to_s.match?(/\bfestival\b/i)
    end

    def valid?(name:, city:, country_code:)
      name.present? && city.present? && country_code == 'ES'
    end

    def fingerprint_for(source_url:, source_event_id:, name:, city:, venue_name:, start_date:)
      source_value = source_event_id.presence || source_url.presence
      payload = if source_value.present?
                  "songkick:#{source_value}"
                else
                  [name, city, venue_name, start_date].map { |value| value.to_s.downcase.squish }.join('|')
                end
      Digest::SHA256.hexdigest(payload)
    end

    def event_dedupe_key_for(name:, city:, venue_name:, start_at:, start_date:)
      normalized_parts = [
        canonical_text(name),
        canonical_text(venue_name),
        canonical_text(city),
        event_time_key(start_at, start_date)
      ].reject(&:blank?)
      return nil if normalized_parts.size < 3

      Digest::SHA256.hexdigest(normalized_parts.join('|'))
    end

    def event_time_key(start_at, start_date)
      return start_at.utc.strftime('%Y-%m-%dT%H:%M') if start_at.present?
      return start_date.iso8601 if start_date.present?

      nil
    end

    def canonical_text(value)
      I18n.transliterate(value.to_s).downcase.squish.presence
    end
  end
end
