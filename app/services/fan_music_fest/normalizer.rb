require 'date'
require 'digest'

module FanMusicFest
  class Normalizer
    SOURCE = 'fanmusicfest'.freeze
    SPAIN_COUNTRY_NAMES = %w[ES Espana España Spain].freeze
    PORTUGAL_COUNTRY_NAMES = %w[PT Portugal].freeze

    def normalize(raw_payload)
      raw = stringify_hash(raw_payload)
      location = stringify_hash(raw['location'])
      address = stringify_hash(location['address'])
      geo = stringify_hash(location['geo'])

      source_url = source_url_for(raw)
      organizer_name = clean_text(dig_hash(raw, 'organizer', 'name'))
      edition_title = clean_title(raw['name'])
      display_name = clean_festival_name(organizer_name.presence || edition_title)
      city = clean_text(address['addressLocality'])
      state = clean_text(address['addressRegion'])
      country = clean_text(address['addressCountry'])
      country_code = country_code_for(country)
      latitude = decimal_or_nil(geo['latitude'])
      longitude = decimal_or_nil(geo['longitude'])
      start_date = parse_date(raw['startDate'])
      end_date = parse_date(raw['endDate'])

      {
        source: SOURCE,
        source_url: source_url,
        source_event_id: source_event_id_for(raw, source_url),
        fingerprint: fingerprint_for(source_url: source_url, name: display_name, city: city, start_date: start_date),
        name: display_name,
        edition_title: edition_title,
        description: clean_text(raw['description']).presence || 'Festival importado desde FanMusicFest. Revisa la informacion antes de publicarlo.',
        address: address_for(location: location, address: address, city: city, state: state, country: country),
        city: city,
        state: state,
        country: country,
        country_code: country_code,
        latitude: latitude,
        longitude: longitude,
        start_date: start_date,
        end_date: end_date,
        image_url: image_url_for(raw['image']),
        free: raw['isAccessibleForFree'],
        event_status: raw['eventStatus'],
        organizer: stringify_hash(raw['organizer']),
        offers: raw['offers'],
        valid: valid?(name: display_name, city: city, country_code: country_code, latitude: latitude, longitude: longitude),
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

    def source_url_for(raw)
      raw['url'].presence || raw['@id'].to_s.sub(/#event\z/, '').presence
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

    def valid?(name:, city:, country_code:, latitude:, longitude:)
      name.present? && city.present? && country_code == 'ES' && latitude.present? && longitude.present?
    end

    def fingerprint_for(source_url:, name:, city:, start_date:)
      Digest::SHA256.hexdigest([source_url, name, city, start_date].compact.join('|'))[0, 32]
    end
  end
end
