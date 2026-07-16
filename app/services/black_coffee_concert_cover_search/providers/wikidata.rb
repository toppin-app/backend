module BlackCoffeeConcertCoverSearch
  module Providers
    class Wikidata < Base
      KEY = 'wikidata'.freeze
      API_URL = 'https://www.wikidata.org/w/api.php'.freeze
      ENTITY_ID = /\AQ[1-9]\d*\z/.freeze
      REFERENCE_PROPERTIES = %w[P31 P106 P136 P27 P495 P740].freeze
      MUSICAL_DESCRIPTION = /\b(music|musical|musician|singer|rapper|composer|disc jockey|dj|band|orchestra|record producer)\b/i.freeze

      attr_reader :requests_count

      def initialize(client: HttpClient.new(allowed_hosts: %w[www.wikidata.org wikidata.org]), result_limit: 8)
        @client = client
        @result_limit = [[result_limit.to_i, 1].max, 20].min
        @requests_count = 0
      end

      def search(context)
        artist = artist_from(context)
        before = requests_count
        qids = seeded_qids(artist, identities_from(context))
        lookup_errors = []

        if qids.empty? && artist.songkick_id.present?
          linked = request_json(
            action: 'query',
            list: 'search',
            srsearch: "haswbstatement:P3478=#{artist.songkick_id}",
            srnamespace: 0,
            srlimit: @result_limit,
            format: 'json',
            maxlag: 5
          )
          if linked.ok?
            qids.concat(Array(linked.json.dig('query', 'search')).filter_map { |entry| valid_qid(entry['title']) })
          else
            lookup_errors << linked
          end
        end

        if qids.empty? && artist.musicbrainz_id.present?
          linked = request_json(
            action: 'query',
            list: 'search',
            srsearch: "haswbstatement:P434=#{artist.musicbrainz_id}",
            srnamespace: 0,
            srlimit: @result_limit,
            format: 'json',
            maxlag: 5
          )
          if linked.ok?
            qids.concat(Array(linked.json.dig('query', 'search')).filter_map { |entry| valid_qid(entry['title']) })
          else
            lookup_errors << linked
          end
        end

        if qids.empty?
          searched = request_json(
            action: 'wbsearchentities',
            search: artist.name,
            language: 'en',
            uselang: 'en',
            type: 'item',
            limit: @result_limit,
            format: 'json',
            maxlag: 5
          )
          return provider_failure(searched, requests_count: requests_count - before) unless searched.ok?

          qids.concat(Array(searched.json['search']).filter_map { |entry| valid_qid(entry['id']) })
        end
        qids = qids.uniq.first(@result_limit)
        return not_found(before, 'Wikidata no devolvio entidades candidatas.', lookup_errors) if qids.empty?

        entities_response = request_json(
          action: 'wbgetentities',
          ids: qids.join('|'),
          props: 'labels|aliases|descriptions|claims|sitelinks',
          languages: 'es|en|mul',
          languagefallback: 1,
          format: 'json',
          maxlag: 5
        )
        return provider_failure(entities_response, requests_count: requests_count - before) unless entities_response.ok?

        entities = entities_response.json.fetch('entities', {}).values.reject { |entity| entity['missing'].present? }
        labels = reference_labels(entities)
        identities = entities.filter_map { |entity| identity_from(entity, labels, artist) }
        return not_found(before, 'Las entidades Wikidata no contienen datos de artista utilizables.', lookup_errors) if identities.empty?

        ProviderResult.ok(
          identities: identities,
          identifiers: merged_identifiers(identities),
          evidence: {
            queried_qids: qids,
            identity_count: identities.size,
            partial_errors: lookup_errors.map(&:error_type).compact.uniq
          },
          requests_count: requests_count - before
        )
      rescue StandardError => e
        ProviderResult.failure(
          status: 'unavailable',
          error_type: 'wikidata_parse_error',
          error_message: "#{e.class}: #{e.message}",
          requests_count: requests_count - before.to_i
        )
      end

      private

      def request_json(params)
        @requests_count += 1
        @client.get(API_URL, params: params)
      end

      def seeded_qids(artist, identities)
        ids = [artist.wikidata_id]
        Array(identities).each { |identity| ids << identity.dig(:identifiers, :wikidata_id) }
        ids.filter_map { |value| valid_qid(value) }.uniq
      end

      def valid_qid(value)
        qid = value.to_s.upcase
        qid if qid.match?(ENTITY_ID)
      end

      def reference_labels(entities)
        ids = entities.flat_map do |entity|
          REFERENCE_PROPERTIES.flat_map { |property| entity_ids(entity, property) }
        end.uniq.first(50)
        return {} if ids.empty?

        response = request_json(
          action: 'wbgetentities',
          ids: ids.join('|'),
          props: 'labels',
          languages: 'es|en|mul',
          languagefallback: 1,
          format: 'json',
          maxlag: 5
        )
        return {} unless response.ok?

        response.json.fetch('entities', {}).each_with_object({}) do |(qid, entity), result|
          result[qid] = localized_values(entity['labels']).first
        end
      end

      def identity_from(entity, reference_labels, artist)
        qid = valid_qid(entity['id'])
        return unless qid

        names = localized_values(entity['labels'])
        aliases = localized_values(entity['aliases'])
        descriptions = localized_values(entity['descriptions'])
        musicbrainz_ids = string_values(entity, 'P434').map(&:downcase).select { |id| id.match?(ArtistContext::MUSICBRAINZ_ID) }.uniq
        songkick_ids = string_values(entity, 'P3478').select { |id| id.match?(/\A[1-9]\d*\z/) }.uniq
        image_files = string_values(entity, 'P18').uniq
        official_urls = string_values(entity, 'P856').uniq
        countries = label_values(entity, %w[P27 P495 P740], reference_labels)
        genres = label_values(entity, ['P136'], reference_labels)
        types = label_values(entity, %w[P31 P106], reference_labels)
        matching_mbid = musicbrainz_ids.find { |id| id == artist.musicbrainz_id } || musicbrainz_ids.first

        {
          provider: KEY,
          name: names.first.to_s,
          aliases: (names.drop(1) + aliases).uniq,
          country: countries.first,
          countries: countries,
          genres: genres,
          types: types,
          descriptions: descriptions,
          official_urls: official_urls,
          image_file: image_files.first,
          sitelinks: entity.fetch('sitelinks', {}).slice('eswiki', 'enwiki').transform_values { |entry| entry['title'] },
          identifiers: {
            wikidata_id: qid,
            musicbrainz_id: matching_mbid,
            songkick_id: songkick_ids.find { |id| id == artist.songkick_id } || songkick_ids.first
          }.compact,
          evidence: {
            musicbrainz_ids: musicbrainz_ids,
            songkick_ids: songkick_ids,
            image_files: image_files,
            musical_entity: (types + descriptions).any? { |value| value.match?(MUSICAL_DESCRIPTION) }
          }
        }
      end

      def localized_values(container)
        case container
        when Hash
          %w[es en mul].filter_map do |language|
            value = container[language]
            value.is_a?(Hash) ? value['value'].to_s.presence : nil
          end + container.values.filter_map { |entry| entry.is_a?(Hash) ? entry['value'].to_s.presence : nil }
        when Array
          container.filter_map { |entry| entry.is_a?(Hash) ? entry['value'].to_s.presence : nil }
        else
          []
        end.uniq
      end

      def claim_values(entity, property)
        Array(entity.dig('claims', property)).sort_by { |claim| claim['rank'] == 'preferred' ? 0 : 1 }.filter_map do |claim|
          claim.dig('mainsnak', 'datavalue', 'value')
        end
      end

      def string_values(entity, property)
        claim_values(entity, property).filter_map { |value| value.is_a?(String) ? value.strip.presence : nil }
      end

      def entity_ids(entity, property)
        claim_values(entity, property).filter_map do |value|
          value.is_a?(Hash) ? valid_qid(value['id'] || value.dig('numeric-id')&.then { |id| "Q#{id}" }) : nil
        end
      end

      def label_values(entity, properties, labels)
        Array(properties).flat_map { |property| entity_ids(entity, property) }.filter_map { |qid| labels[qid] }.uniq
      end

      def merged_identifiers(identities)
        identities.each_with_object({}) do |identity, result|
          identity.fetch(:identifiers, {}).each { |key, value| result[key] ||= value }
        end
      end

      def not_found(before, message, errors)
        transient = errors.find(&:retryable?)
        return provider_failure(transient, requests_count: requests_count - before) if transient

        ProviderResult.failure(
          status: 'not_found',
          error_type: 'wikidata_not_found',
          error_message: message,
          evidence: { partial_errors: errors.map(&:error_type).compact.uniq },
          requests_count: requests_count - before
        )
      end
    end
  end
end
