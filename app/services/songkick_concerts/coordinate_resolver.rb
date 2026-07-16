require 'digest'
require 'json'
require 'nokogiri'
require 'uri'

module SongkickConcerts
  class CoordinateResolver
    Result = Struct.new(
      :status,
      :latitude,
      :longitude,
      :source,
      :confidence,
      :address,
      :street_address,
      :postal_code,
      :city,
      :state,
      :country,
      :venue_name,
      :source_venue_id,
      :evidence,
      :error_type,
      :error_message,
      keyword_init: true
    ) do
      def resolved?
        status == 'resolved' && latitude.present? && longitude.present?
      end

      def ambiguous?
        status == 'ambiguous'
      end

      def retryable?
        status == 'retryable_error'
      end

      def normalized_attributes
        {
          latitude: latitude,
          longitude: longitude,
          coordinates_source: source,
          coordinates_confidence: confidence,
          address: address,
          city: city,
          state: state,
          country: country,
          postal_code: postal_code,
          venue_name: venue_name,
          source_venue_id: source_venue_id,
          coordinates_evidence: evidence
        }.compact
      end
    end

    SPAIN_BOUNDS = {
      latitude: (27.0..44.5),
      longitude: (-19.0..5.0)
    }.freeze
    GOOGLE_RESULT_LIMIT = 5
    MIN_GOOGLE_SCORE = 70
    AMBIGUITY_SCORE_MARGIN = 10
    AMBIGUITY_DISTANCE_METERS = 1_000
    LOCAL_AMBIGUITY_DISTANCE_METERS = 500
    POSITIVE_CACHE_TTL = 180.days
    NEGATIVE_CACHE_TTL = 7.days

    attr_reader :requests_count

    def initialize(
      source_client: SongkickConcerts::Client.new,
      geocoder: GooglePlacesBlackCoffeeClient.new,
      cache: Rails.cache,
      venue_scope: Venue,
      logger: Rails.logger
    )
      @source_client = source_client
      @geocoder = geocoder
      @cache = cache
      @venue_scope = venue_scope
      @logger = logger
      @requests_count = 0
    end

    def resolve(normalized)
      event = normalized.to_h.symbolize_keys
      return rejected('non_concert_source', 'La recuperacion de coordenadas solo acepta fichas /concerts/ de Songkick.') unless concert_source?(event)

      if valid_coordinates?(event[:latitude], event[:longitude])
        return Result.new(
          status: 'resolved',
          latitude: decimal(event[:latitude]),
          longitude: decimal(event[:longitude]),
          source: event[:coordinates_source].presence || 'schema_org',
          confidence: event[:coordinates_confidence].presence || 'high',
          address: event[:address],
          street_address: event[:street_address],
          postal_code: event[:postal_code],
          city: event[:city],
          state: event[:state],
          country: event[:country],
          venue_name: event[:venue_name],
          source_venue_id: event[:source_venue_id],
          evidence: { strategy: 'source_coordinates_already_present' }
        )
      end

      context = location_context(event, {})
      source_location = {}
      unless precise_source_address?(context)
        source_location = source_location_for(event)
        context = location_context(event, source_location)
      end

      if valid_coordinates?(source_location[:latitude], source_location[:longitude])
        result = resolved_result(
          context,
          latitude: source_location[:latitude],
          longitude: source_location[:longitude],
          source: source_location[:coordinates_source].presence || 'songkick_detail',
          confidence: 'high',
          evidence: { strategy: 'source_detail_coordinates', source_url: event[:source_url] }
        )
        log_result(event, result)
        return result
      end

      local_result = resolve_from_local_venues(context)
      if local_result
        log_result(event, local_result)
        return local_result
      end

      unless precise_source_address?(context)
        return rejected(
          'source_address_imprecise',
          'Songkick no ofrece calle y ciudad suficientes; no se asigno el centro de la ciudad como coordenada del concierto.',
          context
        )
      end

      cache_key = cache_key_for(context)
      cached = cached_result(cache_key)
      if cached
        cached.evidence = cached.evidence.to_h.merge(cache_hit: true)
        log_result(event, cached)
        return cached
      end

      result = resolve_with_google(context)
      write_cache(cache_key, result)
      log_result(event, result)
      result
    rescue SongkickConcerts::Client::RobotsBlockedError => e
      result = rejected('source_blocked_by_robots', e.message, event, status: 'unavailable')
      log_result(event, result)
      result
    rescue SongkickConcerts::Client::RequestError => e
      status = e.retryable? ? 'retryable_error' : 'unavailable'
      result = rejected('source_request_error', e.message, event, status: status)
      log_result(event, result)
      result
    rescue StandardError => e
      result = rejected('coordinate_resolution_error', "#{e.class} - #{e.message}", event, status: 'retryable_error')
      log_result(event, result)
      result
    end

    private

    attr_reader :source_client, :geocoder, :cache, :venue_scope, :logger

    def concert_source?(event)
      return false if event[:non_concert_like]

      uri = URI.parse(event[:source_url].to_s)
      uri.scheme == 'https' && uri.host.to_s.downcase.sub(/\Awww\./, '') == 'songkick.com' && uri.path.match?(%r{\A/concerts/\d+})
    rescue URI::InvalidURIError
      false
    end

    def source_location_for(event)
      html = source_client.fetch_event_page(event[:source_url])
      document = Nokogiri::HTML(html.to_s)
      node = exact_event_node(document, event)
      return {} if node.blank?
      return {} if Array(node['@type']).any? { |type| type.to_s.match?(/festival/i) }

      location = stringify_hash(node['location'])
      address = stringify_hash(location['address'])
      geo = stringify_hash(location['geo'])
      venue_href = document.at_css('.venue-container a[href*="/venues/"], a[data-analytics-label="venue_name"][href*="/venues/"]')&.[]('href')

      {
        venue_name: clean(location['name']),
        source_venue_id: venue_href.to_s[%r{/venues/(\d+)}, 1],
        street_address: clean(address['streetAddress']).presence || meta_content(document, 'og:street-address'),
        postal_code: clean(address['postalCode']).presence || meta_content(document, 'og:postal-code'),
        city: clean(address['addressLocality']).presence || meta_content(document, 'og:locality'),
        state: clean(address['addressRegion']),
        country: clean(address['addressCountry']).presence || meta_content(document, 'og:country-name'),
        latitude: geo['latitude'],
        longitude: geo['longitude'],
        coordinates_source: 'songkick_detail_schema_org'
      }
    end

    def exact_event_node(document, event)
      nodes = document.css('script[type="application/ld+json"]').flat_map do |script|
        flatten_json_ld(JSON.parse(script.text))
      rescue JSON::ParserError
        []
      end.select { |entry| event_node?(entry) }
      return nil if nodes.empty?

      expected_id = event[:source_event_id].to_s.presence || event[:source_url].to_s[%r{/concerts/(\d+)}, 1]
      exact = nodes.find do |node|
        [node['url'], node['@id']].compact.any? { |url| url.to_s[%r{/concerts/(\d+)}, 1] == expected_id }
      end
      return exact if exact

      canonical_id = document.at_css('link[rel~="canonical"][href]')&.[]('href').to_s[%r{/concerts/(\d+)}, 1]
      return nil if expected_id.present? && canonical_id.present? && canonical_id != expected_id

      nodes.one? ? nodes.first : nil
    end

    def flatten_json_ld(value)
      case value
      when Array
        value.flat_map { |entry| flatten_json_ld(entry) }
      when Hash
        normalized = stringify_hash(value)
        graph = normalized['@graph']
        [normalized] + (graph ? flatten_json_ld(graph) : [])
      else
        []
      end
    end

    def event_node?(node)
      Array(node['@type']).any? { |type| type.to_s.match?(/MusicEvent|Event/i) }
    end

    def location_context(event, source)
      street = source[:street_address].presence || event[:street_address].presence || street_from_address(event[:address], event)
      postal_code = source[:postal_code].presence || event[:postal_code].presence || postal_code_from(event[:address])
      city = source[:city].presence || event[:city]
      state = source[:state].presence || event[:state]
      country = source[:country].presence || event[:country].presence || 'Spain'
      venue_name = source[:venue_name].presence || event[:venue_name]
      address = format_address(
        street: street,
        postal_code: postal_code,
        venue_name: venue_name,
        city: city,
        state: state,
        country: country
      )

      event.merge(
        address: address.presence || event[:address],
        street_address: street,
        postal_code: postal_code,
        city: city,
        state: state,
        country: country,
        venue_name: venue_name,
        source_venue_id: source[:source_venue_id].presence || event[:source_venue_id]
      )
    end

    def resolve_from_local_venues(context)
      candidates = venue_scope.where.not(category: 'festival').where.not(latitude: nil).where.not(longitude: nil)
      candidates = candidates.where('LOWER(city) = ?', context[:city].to_s.downcase) if context[:city].present?
      scored = candidates.limit(150).filter_map do |venue|
        score, signals = local_match_score(venue, context)
        next if score < 100

        { venue: venue, score: score, signals: signals }
      end.sort_by { |entry| -entry[:score] }
      return nil if scored.empty?

      best = scored.first
      conflicting = scored.drop(1).find do |entry|
        entry[:score] >= best[:score] - AMBIGUITY_SCORE_MARGIN &&
          distance_meters(best[:venue].latitude, best[:venue].longitude, entry[:venue].latitude, entry[:venue].longitude) > LOCAL_AMBIGUITY_DISTANCE_METERS
      end
      if conflicting
        return rejected(
          'ambiguous_local_venue',
          'Hay locales internos con la misma identidad de sala/direccion pero coordenadas incompatibles.',
          context,
          status: 'ambiguous',
          evidence: { strategy: 'local_venue_reuse', candidate_venue_ids: [best[:venue].id, conflicting[:venue].id] }
        )
      end

      resolved_result(
        context,
        latitude: best[:venue].latitude,
        longitude: best[:venue].longitude,
        source: 'local_venue_exact_match',
        confidence: best[:score] >= 170 ? 'high' : 'medium',
        evidence: {
          strategy: 'local_venue_reuse',
          matched_venue_id: best[:venue].id,
          score: best[:score],
          signals: best[:signals]
        }
      )
    rescue ActiveRecord::ActiveRecordError => e
      logger.warn("Songkick coordinate local reuse skipped: #{e.class} - #{e.message}") if logger
      nil
    end

    def precise_source_address?(context)
      context[:street_address].present? && context[:city].present? && context[:country].present?
    end

    def local_match_score(venue, context)
      signals = []
      score = 0
      metadata = venue.respond_to?(:festival_metadata) ? venue.festival_metadata.to_h : {}
      stored_source_venue_id = metadata['source_venue_id'].presence || metadata[:source_venue_id].presence

      if context[:source_venue_id].present? && stored_source_venue_id.to_s == context[:source_venue_id].to_s
        score += 150
        signals << 'source_venue_id'
      end

      venue_name = venue.respond_to?(:festival_venue_name) ? venue.festival_venue_name.presence : nil
      venue_name ||= venue.name
      if equivalent_text?(venue_name, context[:venue_name])
        score += 45
        signals << 'venue_name'
      end

      if address_match?(venue.address, context[:street_address], context[:postal_code])
        score += 70
        signals << 'street_address'
      end

      if equivalent_text?(venue.city, context[:city])
        score += 20
        signals << 'city'
      end

      [score, signals]
    end

    def resolve_with_google(context)
      query = geocoding_query(context)
      @requests_count += 1
      places = geocoder.geocode_address(query: query, limit: GOOGLE_RESULT_LIMIT, country_code: 'ES')
      candidates = Array(places).filter_map { |place| google_candidate(place, context) }
        .select { |candidate| candidate[:score] >= MIN_GOOGLE_SCORE }
        .sort_by { |candidate| -candidate[:score] }

      return rejected('geocoding_not_found', 'Google Places no devolvio una coincidencia suficientemente precisa para la direccion de Songkick.', context, evidence: { strategy: 'google_places_address', query: query }) if candidates.empty?

      best = candidates.first
      conflicting = candidates.drop(1).find do |candidate|
        candidate[:score] >= best[:score] - AMBIGUITY_SCORE_MARGIN &&
          distance_meters(best[:latitude], best[:longitude], candidate[:latitude], candidate[:longitude]) > AMBIGUITY_DISTANCE_METERS
      end
      if conflicting
        return rejected(
          'ambiguous_geocoding',
          'La direccion coincide con varios lugares alejados y no se asignaron coordenadas automaticamente.',
          context,
          status: 'ambiguous',
          evidence: {
            strategy: 'google_places_address',
            query: query,
            candidate_place_ids: [best[:place_id], conflicting[:place_id]],
            scores: [best[:score], conflicting[:score]]
          }
        )
      end

      resolved_result(
        context,
        latitude: best[:latitude],
        longitude: best[:longitude],
        source: 'google_places_address',
        confidence: best[:score] >= 120 ? 'high' : 'medium',
        evidence: {
          strategy: 'google_places_address',
          query: query,
          google_place_id: best[:place_id],
          score: best[:score],
          signals: best[:signals],
          formatted_address: best[:formatted_address]
        }
      )
    rescue GooglePlacesBlackCoffeeClient::MissingApiKeyError => e
      rejected('geocoder_unavailable', e.message, context, status: 'unavailable', evidence: { strategy: 'google_places_address' })
    rescue GooglePlacesBlackCoffeeClient::RequestError => e
      rejected('geocoder_request_error', e.message, context, status: 'retryable_error', evidence: { strategy: 'google_places_address' })
    end

    def google_candidate(place, context)
      payload = stringify_hash(place)
      latitude = payload.dig('location', 'latitude')
      longitude = payload.dig('location', 'longitude')
      return nil unless valid_coordinates?(latitude, longitude)

      components = Array(payload['addressComponents'])
      country_code = component_value(components, 'country', key: 'shortText')
      formatted = clean(payload['formattedAddress'])
      return nil unless country_code.to_s.casecmp('ES').zero? || canonical_text(formatted).match?(/\bspain\b|\bespana\b/)

      candidate_city = %w[locality postal_town administrative_area_level_2].filter_map do |type|
        component_value(components, type)
      end.first
      return nil if context[:city].present? && !equivalent_or_contains?(candidate_city.presence || formatted, context[:city])

      candidate_postal = component_value(components, 'postal_code')
      if context[:postal_code].present? && candidate_postal.present? && candidate_postal.to_s != context[:postal_code].to_s
        return nil
      end
      street_match = address_match?(formatted, context[:street_address], nil)
      return nil if context[:street_address].present? && !street_match

      signals = ['country']
      score = 10
      if equivalent_or_contains?(candidate_city.presence || formatted, context[:city])
        score += 25
        signals << 'city'
      end
      if street_match
        score += 55
        signals << 'street_address'
      end
      if context[:postal_code].present? && candidate_postal.to_s == context[:postal_code].to_s
        score += 30
        signals << 'postal_code'
      end
      display_name = payload.dig('displayName', 'text')
      if equivalent_or_contains?(display_name, context[:venue_name])
        score += 35
        signals << 'venue_name'
      end

      {
        latitude: decimal(latitude),
        longitude: decimal(longitude),
        place_id: payload['id'].presence || payload['name'].to_s.split('/').last.presence,
        formatted_address: formatted,
        score: score,
        signals: signals
      }
    end

    def geocoding_query(context)
      [context[:venue_name], context[:street_address], context[:postal_code], context[:city], context[:state], context[:country].presence || 'Spain']
        .compact
        .reject(&:blank?)
        .uniq
        .join(', ')
    end

    def cache_key_for(context)
      identity = [context[:source_venue_id], context[:venue_name], context[:street_address], context[:postal_code], context[:city], 'ES']
        .map { |value| canonical_text(value) }
        .join('|')
      "songkick:concert_coordinates:v1:#{Digest::SHA256.hexdigest(identity)}"
    end

    def cached_result(key)
      payload = cache.read(key)
      return nil unless payload.respond_to?(:symbolize_keys)

      Result.new(**payload.symbolize_keys)
    rescue StandardError
      nil
    end

    def write_cache(key, result)
      return if result.retryable? || result.status == 'unavailable'

      ttl = result.resolved? ? POSITIVE_CACHE_TTL : NEGATIVE_CACHE_TTL
      cache.write(key, result.to_h, expires_in: ttl)
    rescue StandardError => e
      logger.warn("Songkick coordinate cache write skipped: #{e.class} - #{e.message}") if logger
    end

    def resolved_result(context, latitude:, longitude:, source:, confidence:, evidence:)
      Result.new(
        status: 'resolved',
        latitude: decimal(latitude),
        longitude: decimal(longitude),
        source: source,
        confidence: confidence,
        address: context[:address],
        street_address: context[:street_address],
        postal_code: context[:postal_code],
        city: context[:city],
        state: context[:state],
        country: context[:country],
        venue_name: context[:venue_name],
        source_venue_id: context[:source_venue_id],
        evidence: evidence
      )
    end

    def rejected(error_type, message, context = {}, status: 'not_found', evidence: nil)
      Result.new(
        status: status,
        address: context[:address],
        street_address: context[:street_address],
        postal_code: context[:postal_code],
        city: context[:city],
        state: context[:state],
        country: context[:country],
        venue_name: context[:venue_name],
        source_venue_id: context[:source_venue_id],
        evidence: evidence,
        error_type: error_type,
        error_message: message
      )
    end

    def format_address(street:, postal_code:, venue_name:, city:, state:, country:)
      [street, venue_name, postal_code, city, state, country]
        .compact
        .map { |value| clean(value) }
        .reject(&:blank?)
        .uniq { |value| canonical_text(value) }
        .join(', ')
        .presence
    end

    def street_from_address(address, event)
      value = clean(address)
      return nil if value.blank?

      removable = [event[:venue_name], event[:postal_code], event[:city], event[:state], event[:country], 'Spain', 'Espana', 'España']
        .compact
        .map { |entry| Regexp.escape(entry.to_s) }
      cleaned = value.dup
      removable.each { |entry| cleaned.gsub!(/(?:\A|,\s*)#{entry}(?=,|\z)/i, '') }
      cleaned.split(',').map(&:strip).find { |part| part.match?(/\d/) }.presence
    end

    def postal_code_from(address)
      clean(address).to_s[/\b\d{5}\b/]
    end

    def address_match?(candidate, expected_street, expected_postal)
      return false if candidate.blank? || expected_street.blank?

      candidate_text = canonical_text(candidate)
      street_text = canonical_text(expected_street)
      street_tokens = street_text.split.reject { |token| token.length < 2 }
      street_match = candidate_text.include?(street_text) || street_tokens.all? { |token| candidate_text.split.include?(token) }
      postal_match = expected_postal.blank? || candidate_text.split.include?(canonical_text(expected_postal))
      street_match && postal_match
    end

    def equivalent_text?(left, right)
      left_text = canonical_text(left)
      right_text = canonical_text(right)
      left_text.present? && left_text == right_text
    end

    def equivalent_or_contains?(left, right)
      left_text = canonical_text(left)
      right_text = canonical_text(right)
      return false if left_text.blank? || right_text.blank?

      left_text == right_text || left_text.include?(right_text) || right_text.include?(left_text)
    end

    def canonical_text(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
    end

    def clean(value)
      ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
    end

    def stringify_hash(value)
      return {} unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, entry), result|
        result[key.to_s] = entry.is_a?(Hash) ? stringify_hash(entry) : entry
      end
    end

    def meta_content(document, property)
      clean(document.at_css("meta[property='#{property}'][content]")&.[]('content'))
    end

    def component_value(components, type, key: 'longText')
      component = Array(components).find { |entry| Array(entry['types']).include?(type) }
      component&.dig(key).presence || component&.dig('longText').presence || component&.dig('shortText')
    end

    def valid_coordinates?(latitude, longitude)
      lat = Float(latitude)
      lng = Float(longitude)
      lat.finite? && lng.finite? && SPAIN_BOUNDS[:latitude].cover?(lat) && SPAIN_BOUNDS[:longitude].cover?(lng)
    rescue ArgumentError, TypeError
      false
    end

    def decimal(value)
      BigDecimal(value.to_s)
    end

    def distance_meters(lat1, lng1, lat2, lng2)
      radius = 6_371_000.0
      phi1 = Float(lat1) * Math::PI / 180.0
      phi2 = Float(lat2) * Math::PI / 180.0
      delta_phi = (Float(lat2) - Float(lat1)) * Math::PI / 180.0
      delta_lambda = (Float(lng2) - Float(lng1)) * Math::PI / 180.0
      a = Math.sin(delta_phi / 2.0)**2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(delta_lambda / 2.0)**2
      radius * 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))
    rescue ArgumentError, TypeError
      Float::INFINITY
    end

    def log_result(event, result)
      return unless logger

      logger.info(
        {
          event: 'songkick_concert_coordinate_resolution',
          source_event_id: event[:source_event_id],
          source_url: event[:source_url],
          venue_name: result.venue_name,
          status: result.status,
          coordinates_source: result.source,
          coordinates_confidence: result.confidence,
          error_type: result.error_type,
          evidence: result.evidence
        }.compact.to_json
      )
    end
  end
end
