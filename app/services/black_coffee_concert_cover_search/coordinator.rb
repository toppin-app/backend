module BlackCoffeeConcertCoverSearch
  class Coordinator
    attr_reader :requests_count

    def initialize(providers: nil, matcher: Matcher.new, logger: Rails.logger)
      @providers = providers || default_providers
      @matcher = matcher
      @logger = logger
      @requests_count = 0
    end

    def search(event)
      artist = ArtistContext.build(event)
      return invalid_event_result(artist) unless artist.valid?

      state = { event: event, artist: artist, identities: [], candidates: [] }
      attempts = []
      @providers.each do |provider|
        result = call_provider(provider, state)
        @requests_count += result.requests_count.to_i
        state[:identities].concat(Array(result.identities))
        state[:candidates].concat(Array(result.candidates))
        state[:identities].uniq! { |identity| identity_fingerprint(identity) }
        state[:candidates].uniq! { |candidate| [candidate.provider, candidate.image_url, candidate.identifiers.to_h] }
        attempts << provider_attempt(provider, result)
        log_provider_attempt(attempts.last)
      end

      matched = @matcher.match(
        artist: artist,
        identities: state[:identities],
        candidates: state[:candidates]
      )
      return matched_result(matched, artist, attempts) if %w[found ambiguous].include?(matched.status)

      unresolved_result(matched, artist, attempts)
    rescue StandardError => e
      SearchResult.new(
        status: 'unavailable',
        confidence: 0,
        identifiers: {},
        provider_attempts: defined?(attempts) ? attempts : [],
        evidence: { exception_class: e.class.name },
        error_type: 'coordinator_error',
        error_message: e.message
      )
    end

    private

    def default_providers
      [
        Providers::MusicBrainz.new,
        Providers::Wikidata.new,
        Providers::WikimediaCommons.new
      ]
    end

    def call_provider(provider, state)
      result = provider.search(state)
      return result if result.is_a?(ProviderResult)

      ProviderResult.failure(
        status: 'unavailable',
        error_type: 'invalid_provider_result',
        error_message: "#{provider_key(provider)} no devolvio ProviderResult."
      )
    rescue StandardError => e
      ProviderResult.failure(
        status: 'unavailable',
        error_type: 'provider_exception',
        error_message: "#{e.class}: #{e.message}"
      )
    end

    def provider_attempt(provider, result)
      {
        provider: provider_key(provider),
        status: result.status,
        requests_count: result.requests_count.to_i,
        identities_count: Array(result.identities).size,
        candidates_count: Array(result.candidates).size,
        identifiers: result.identifiers.to_h,
        evidence: result.evidence.to_h,
        error_type: result.error_type,
        error_message: result.error_message
      }.compact
    end

    def provider_key(provider)
      provider.respond_to?(:key) ? provider.key.to_s : provider.class.name.demodulize.underscore
    end

    def identity_fingerprint(identity)
      identifiers = value(identity, :identifiers).to_h
      stable_id = identifiers[:wikidata_id] || identifiers['wikidata_id'] ||
        identifiers[:musicbrainz_id] || identifiers['musicbrainz_id'] ||
        identifiers[:songkick_id] || identifiers['songkick_id'] ||
        [value(identity, :provider), value(identity, :name), value(identity, :country)]
      [value(identity, :provider).to_s, stable_id]
    end

    def value(object, key)
      return unless object.respond_to?(:to_h)

      object.to_h[key] || object.to_h[key.to_s]
    end

    def matched_result(matched, artist, attempts)
      if matched.status == 'found'
        return SearchResult.new(
          status: 'found',
          candidate: matched.candidate,
          confidence: matched.confidence,
          identifiers: matched.identifiers.to_h,
          provider_attempts: attempts,
          evidence: result_evidence(artist, matched)
        )
      end

      SearchResult.new(
        status: 'ambiguous',
        confidence: matched.confidence,
        identifiers: {},
        provider_attempts: attempts,
        evidence: result_evidence(artist, matched),
        error_type: 'ambiguous_artist_identity',
        error_message: matched.evidence.to_h[:ambiguity_reason] || 'No se pudo confirmar una unica identidad artistica.'
      )
    end

    def unresolved_result(matched, artist, attempts)
      retryable = attempts.find { |attempt| attempt[:status] == 'retryable_error' }
      unavailable = attempts.find { |attempt| attempt[:status] == 'unavailable' }
      status = retryable ? 'retryable_error' : (unavailable ? 'unavailable' : 'not_found')
      source = retryable || unavailable
      SearchResult.new(
        status: status,
        confidence: matched.confidence,
        identifiers: {},
        provider_attempts: attempts,
        evidence: result_evidence(artist, matched),
        error_type: source&.dig(:error_type) || 'external_image_not_found',
        error_message: source&.dig(:error_message) || 'No se encontro una imagen externa con identidad y licencia verificables.'
      )
    end

    def invalid_event_result(artist)
      SearchResult.new(
        status: 'unavailable',
        confidence: 0,
        identifiers: {},
        provider_attempts: [],
        evidence: { artist_context: artist.to_h.except(:raw) },
        error_type: 'missing_artist_name',
        error_message: 'El concierto no contiene un artista principal utilizable.'
      )
    end

    def result_evidence(artist, matched)
      evidence = {
        artist_context: artist.to_h.except(:raw),
        matcher: matched.evidence.to_h
      }
      evidence[:selected_candidate] = matched.candidate.evidence.to_h if matched.candidate
      evidence
    end

    def log_provider_attempt(attempt)
      @logger&.debug(
        "[concert-cover-search] provider=#{attempt[:provider]} status=#{attempt[:status]} " \
        "requests=#{attempt[:requests_count]} identities=#{attempt[:identities_count]} " \
        "candidates=#{attempt[:candidates_count]} error=#{attempt[:error_type].inspect}"
      )
    end
  end
end
