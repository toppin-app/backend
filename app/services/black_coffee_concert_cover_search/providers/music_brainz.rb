module BlackCoffeeConcertCoverSearch
  module Providers
    class MusicBrainz < Base
      KEY = 'musicbrainz'.freeze
      API_URL = 'https://musicbrainz.org/ws/2'.freeze
      DEFAULT_RESULT_LIMIT = 5
      DEFAULT_LOOKUP_LIMIT = 3
      SONGKICK_PATH = %r{/artists/([1-9]\d*)}.freeze
      WIKIDATA_PATH = %r{/wiki/(Q[1-9]\d*)}i.freeze

      attr_reader :requests_count

      def initialize(
        client: HttpClient.new(allowed_hosts: ['musicbrainz.org']),
        minimum_interval: ENV.fetch('MUSICBRAINZ_REQUEST_INTERVAL_SECONDS', '1.0'),
        result_limit: DEFAULT_RESULT_LIMIT,
        lookup_limit: DEFAULT_LOOKUP_LIMIT,
        sleeper: ->(seconds) { sleep(seconds) },
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      )
        @client = client
        @minimum_interval = [minimum_interval.to_f, 1.0].max
        @result_limit = [[result_limit.to_i, 1].max, 10].min
        @lookup_limit = [[lookup_limit.to_i, 1].max, @result_limit].min
        @sleeper = sleeper
        @clock = clock
        @last_request_at = nil
        @requests_count = 0
      end

      def search(context)
        artist = artist_from(context)
        before = requests_count
        response = throttled_get(
          "#{API_URL}/artist",
          params: {
            query: %(artist:"#{escape_query(artist.name)}"),
            fmt: 'json',
            limit: @result_limit
          }
        )
        return provider_failure(response, requests_count: requests_count - before) unless response.ok?

        raw_matches = Array(response.json['artists'])
        return not_found(before, 'MusicBrainz no devolvio artistas.') if raw_matches.empty?

        identities = []
        lookup_failures = []
        prioritized_matches(raw_matches, artist).first(@lookup_limit).each do |raw_match|
          mbid = raw_match['id'].to_s
          next unless mbid.match?(ArtistContext::MUSICBRAINZ_ID)

          detail = throttled_get(
            "#{API_URL}/artist/#{mbid}",
            params: { fmt: 'json', inc: 'aliases+genres+url-rels' }
          )
          unless detail.ok?
            lookup_failures << detail
            next
          end

          identities << identity_from(detail.json, raw_match)
        end

        if identities.empty? && lookup_failures.any?
          failure = lookup_failures.find(&:retryable?) || lookup_failures.first
          return provider_failure(failure, requests_count: requests_count - before)
        end
        return not_found(before, 'Ningun resultado de MusicBrainz pudo validarse.') if identities.empty?

        ProviderResult.ok(
          identities: identities,
          identifiers: merged_identifiers(identities),
          evidence: {
            result_count: raw_matches.size,
            looked_up_count: identities.size,
            partial_lookup_errors: lookup_failures.map(&:error_type).compact.uniq
          },
          requests_count: requests_count - before
        )
      rescue StandardError => e
        ProviderResult.failure(
          status: 'unavailable',
          error_type: 'musicbrainz_parse_error',
          error_message: "#{e.class}: #{e.message}",
          requests_count: requests_count - before.to_i
        )
      end

      private

      def throttled_get(url, params:)
        if @last_request_at
          remaining = @minimum_interval - (@clock.call - @last_request_at)
          @sleeper.call(remaining) if remaining.positive?
        end
        response = @client.get(url, params: params)
        @requests_count += 1
        @last_request_at = @clock.call
        response
      end

      def escape_query(value)
        value.to_s.gsub(/([\\"])/, '\\\\\1')
      end

      def prioritized_matches(matches, artist)
        canonical_name = canonical(artist.name)
        Array(matches).sort_by do |match|
          exact = canonical(match['name']) == canonical_name || Array(match['aliases']).any? { |entry| canonical(entry['name']) == canonical_name }
          [exact ? 0 : 1, -match['score'].to_i]
        end
      end

      def identity_from(detail, search_match)
        urls = Array(detail['relations']).filter_map { |relation| relation.dig('url', 'resource').to_s.presence }.uniq
        {
          provider: KEY,
          name: detail['name'].to_s,
          aliases: Array(detail['aliases']).filter_map { |entry| entry['name'].to_s.presence }.uniq,
          country: detail['country'].to_s.presence || detail.dig('area', 'name').to_s.presence,
          genres: (Array(detail['genres']) + Array(detail['tags'])).filter_map { |entry| entry['name'].to_s.presence }.uniq,
          official_urls: urls.reject { |url| url.match?(SONGKICK_PATH) || url.match?(WIKIDATA_PATH) },
          identifiers: {
            musicbrainz_id: detail['id'].to_s.downcase,
            songkick_id: urls.filter_map { |url| url[SONGKICK_PATH, 1] }.first,
            wikidata_id: urls.filter_map { |url| url[WIKIDATA_PATH, 1]&.upcase }.first
          }.compact,
          evidence: {
            search_score: search_match['score'].to_i,
            disambiguation: detail['disambiguation'].to_s.presence,
            relation_urls: urls
          }.compact
        }
      end

      def merged_identifiers(identities)
        identities.each_with_object({}) do |identity, result|
          identity.fetch(:identifiers, {}).each { |key, value| result[key] ||= value }
        end
      end

      def canonical(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
      end

      def not_found(before, message)
        ProviderResult.failure(
          status: 'not_found',
          error_type: 'musicbrainz_not_found',
          error_message: message,
          requests_count: requests_count - before
        )
      end
    end
  end
end
