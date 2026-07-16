require 'uri'

module BlackCoffeeConcertCoverSearch
  ArtistContext = Struct.new(
    :name,
    :aliases,
    :country,
    :genres,
    :official_urls,
    :songkick_id,
    :musicbrainz_id,
    :wikidata_id,
    :raw,
    keyword_init: true
  ) do
    const_set(:SONGKICK_ARTIST_PATH, %r{/artists/([1-9]\d*)}.freeze)
    const_set(:MUSICBRAINZ_ID, /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze)
    const_set(:WIKIDATA_ID, /\AQ[1-9]\d*\z/i.freeze)

    def self.build(event)
      payload = deep_stringify(event.respond_to?(:to_h) ? event.to_h : {})
      raw_payload = payload['raw_payload'].is_a?(Hash) ? payload['raw_payload'] : {}
      raw_performer = first_performer(raw_payload['performer']) || first_performer(payload['performer'])
      normalized_performer = first_performer(payload['performer_details']) || first_performer(payload['performers'])
      performer = raw_performer || normalized_performer

      performer_name = performer.is_a?(Hash) ? performer['name'] : performer
      same_as = if performer.is_a?(Hash)
                  Array(performer['sameAs'] || performer['same_as']) +
                    Array(performer['url'] || performer['source_url']) +
                    Array(performer['official_url'])
                else
                  []
                end
      explicit_urls =
        Array(payload['artist_official_urls']) +
        Array(payload['artist_official_url'] || payload['official_url']) +
        Array(payload['artist_source_url'])
      artist_urls = (same_as + explicit_urls).filter_map { |value| safe_url(value) }.uniq
      songkick_id = clean_id(payload['songkick_artist_id'] || payload['source_artist_id']) || songkick_id_from(artist_urls)
      genres = if performer.is_a?(Hash)
                 Array(performer['genre'] || performer['genres'])
               else
                 []
               end
      genres = (genres + Array(payload['genres'])).map { |value| clean_text(value) }.compact.uniq

      performer_aliases = if performer.is_a?(Hash)
                            Array(performer['alternateName'] || performer['alternate_name'] || performer['aliases'])
                          else
                            []
                          end

      new(
        name: clean_text(payload['artist_name']) || clean_text(performer_name) || fallback_name(payload),
        aliases: (Array(payload['artist_aliases']) + performer_aliases).map { |value| clean_text(value) }.compact.uniq,
        country: clean_text(payload['artist_country'] || payload['country_code'] || (performer.is_a?(Hash) && (performer['country'] || performer['country_code']))),
        genres: genres,
        official_urls: artist_urls.reject { |url| songkick_url?(url) },
        songkick_id: songkick_id,
        musicbrainz_id: valid_musicbrainz_id(payload['musicbrainz_id'] || payload['mbid']),
        wikidata_id: valid_wikidata_id(payload['wikidata_id'] || payload['qid']),
        raw: payload
      )
    end

    def valid?
      name.present?
    end

    def stable_identifiers
      {
        songkick_id: songkick_id,
        musicbrainz_id: musicbrainz_id,
        wikidata_id: wikidata_id
      }.compact
    end

    class << self
      private

      def deep_stringify(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), result| result[key.to_s] = deep_stringify(entry) }
        when Array
          value.map { |entry| deep_stringify(entry) }
        else
          value
        end
      end

      def first_performer(value)
        return value.find { |entry| entry.present? } if value.is_a?(Array)

        value if value.present?
      end

      def fallback_name(payload)
        clean_text(payload['name'].to_s.split(/\s+(?:at|@)\s+/i).first)
      end

      def clean_text(value)
        ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
      end

      def clean_id(value)
        value.to_s.strip.presence
      end

      def safe_url(value)
        uri = URI.parse(value.to_s.strip)
        return unless uri.is_a?(URI::HTTP) && uri.host.present?

        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def songkick_id_from(urls)
        Array(urls).filter_map { |url| URI.parse(url).path[SONGKICK_ARTIST_PATH, 1] }.first
      rescue URI::InvalidURIError
        nil
      end

      def songkick_url?(url)
        URI.parse(url).host.to_s.downcase.sub(/\Awww\./, '') == 'songkick.com'
      rescue URI::InvalidURIError
        false
      end

      def valid_musicbrainz_id(value)
        id = clean_id(value)
        id&.match?(MUSICBRAINZ_ID) ? id.downcase : nil
      end

      def valid_wikidata_id(value)
        id = clean_id(value)
        id&.match?(WIKIDATA_ID) ? id.upcase : nil
      end
    end
  end
end
