require 'uri'

module BlackCoffeeConcertCoverSearch
  class Matcher
    ACCEPTANCE_SCORE = 75
    MIN_STRUCTURED_SIGNALS = 3
    AMBIGUITY_MARGIN = 10
    MIN_IMAGE_SIDE = 300

    MatchResult = Struct.new(
      :status,
      :candidate,
      :confidence,
      :identifiers,
      :evidence,
      keyword_init: true
    )

    def match(artist:, identities:, candidates:)
      ranked = Array(candidates).filter_map { |candidate| score(candidate, artist, Array(identities)) }
      ranked = deduplicate_identities(ranked).sort_by { |entry| -entry[:score] }
      safe = ranked.select { |entry| entry[:safe] }

      if safe.any?
        top = safe.first
        challenger = safe.second
        if challenger && top[:identity_key] != challenger[:identity_key] && (top[:score] - challenger[:score]).abs <= AMBIGUITY_MARGIN
          return ambiguous_result(ranked, 'Dos identidades distintas superan el umbral con puntuaciones demasiado proximas.')
        end

        if !top[:definitive] && (plausible_challenger = ranked.find { |entry| entry[:identity_key] != top[:identity_key] && entry[:plausible] })
          if top[:score] - plausible_challenger[:score] <= AMBIGUITY_MARGIN
            return ambiguous_result(ranked, 'Una segunda identidad plausible queda dentro del margen de ambiguedad.')
          end
        end

        return MatchResult.new(
          status: 'found',
          candidate: top[:candidate],
          confidence: [top[:score], 100].min,
          identifiers: top[:identifiers],
          evidence: match_evidence(ranked).merge(selected_signals: top[:signals], definitive_match: top[:definitive])
        )
      end

      return ambiguous_result(ranked, 'Hay imagenes de artistas homonimos o faltan señales estructuradas para publicar automaticamente.') if ranked.any? { |entry| entry[:plausible] }

      MatchResult.new(status: 'not_found', confidence: 0, identifiers: {}, evidence: match_evidence(ranked))
    end

    private

    def score(candidate, artist, identities)
      identity = candidate.evidence.to_h[:identity] || candidate.evidence.to_h['identity'] || {}
      identifiers = normalized_identifiers(candidate.identifiers.to_h.merge(identity_identifiers(identity)))
      names = identity_names(identity)
      name_exact = names.any? { |name| equivalent_name?(name, artist.name) } || Array(artist.aliases).any? { |name| names.any? { |candidate_name| equivalent_name?(name, candidate_name) } }
      return rejected(candidate, identifiers, 'name_mismatch') unless name_exact

      min_side = [candidate.width.to_i, candidate.height.to_i].min
      return rejected(candidate, identifiers, 'image_too_small') if min_side < MIN_IMAGE_SIDE

      linked_musicbrainz = linked_musicbrainz_identities(identity, identities)
      all_songkick_ids = identity_values(identity, :songkick_ids) + [identifiers[:songkick_id]] + linked_musicbrainz.map { |entry| identity_identifiers(entry)[:songkick_id] }
      all_musicbrainz_ids = identity_values(identity, :musicbrainz_ids).map(&:downcase) + [identifiers[:musicbrainz_id].to_s.downcase]
      all_wikidata_ids = [identifiers[:wikidata_id]] + linked_musicbrainz.map { |entry| identity_identifiers(entry)[:wikidata_id] }
      all_songkick_ids = all_songkick_ids.compact.map(&:to_s).uniq
      all_musicbrainz_ids = all_musicbrainz_ids.reject(&:blank?).uniq
      all_wikidata_ids = all_wikidata_ids.compact.map { |value| value.to_s.upcase }.uniq

      required_identifier_conflict =
        identifier_conflict?(artist.songkick_id, all_songkick_ids) ||
        identifier_conflict?(artist.musicbrainz_id&.downcase, all_musicbrainz_ids) ||
        identifier_conflict?(artist.wikidata_id&.upcase, all_wikidata_ids)
      return rejected(candidate, identifiers, 'stable_identifier_conflict') if required_identifier_conflict

      score = 20
      signals = []
      definitive = false

      songkick_exact = artist.songkick_id.present? && all_songkick_ids.include?(artist.songkick_id.to_s)
      musicbrainz_exact = artist.musicbrainz_id.present? && all_musicbrainz_ids.include?(artist.musicbrainz_id.downcase)
      wikidata_exact = artist.wikidata_id.present? && all_wikidata_ids.include?(artist.wikidata_id.upcase)
      if songkick_exact
        score += 65
        signals << 'songkick_id_crosslink'
        definitive = true
      end
      if musicbrainz_exact
        score += 55
        signals << 'known_musicbrainz_id'
        definitive = true
      end
      if wikidata_exact
        score += 55
        signals << 'known_wikidata_id'
        definitive = true
      end

      mbid_crosslink = linked_musicbrainz.any? do |entry|
        entry_ids = identity_identifiers(entry)
        all_musicbrainz_ids.include?(entry_ids[:musicbrainz_id].to_s.downcase)
      end
      qid_crosslink = linked_musicbrainz.any? do |entry|
        qid = identity_identifiers(entry)[:wikidata_id].to_s.upcase
        qid.present? && all_wikidata_ids.include?(qid)
      end
      if mbid_crosslink
        score += 30
        signals << 'musicbrainz_wikidata_crosslink'
      end
      if qid_crosslink
        score += 25
        signals << 'musicbrainz_qid_crosslink'
      end

      if musical_entity?(identity)
        score += 10
        signals << 'musical_entity_type'
      end
      if country_match?(artist, identity)
        score += 10
        signals << 'country_match'
      end
      if genre_match?(artist, identity)
        score += 10
        signals << 'genre_match'
      end
      if official_url_match?(artist, identity)
        score += 15
        signals << 'official_url_match'
      end

      score += min_side >= 600 ? 10 : 7
      required_stable_id_present = artist.stable_identifiers.any?
      all_required_ids_matched =
        (!artist.songkick_id.present? || songkick_exact) &&
        (!artist.musicbrainz_id.present? || musicbrainz_exact) &&
        (!artist.wikidata_id.present? || wikidata_exact)
      safe = if required_stable_id_present
               all_required_ids_matched && definitive
             else
               signals.uniq.size >= MIN_STRUCTURED_SIGNALS && score >= ACCEPTANCE_SCORE
             end

      {
        candidate: candidate,
        identity_key: identity_key(identifiers, candidate),
        identifiers: identifiers,
        score: [score, 100].min,
        signals: signals.uniq,
        definitive: definitive,
        safe: safe,
        plausible: true
      }
    end

    def linked_musicbrainz_identities(identity, identities)
      ids = normalized_identifiers(identity_identifiers(identity))
      mbids = (identity_values(identity, :musicbrainz_ids) + [ids[:musicbrainz_id]]).compact.map { |value| value.to_s.downcase }
      qid = ids[:wikidata_id].to_s.upcase
      songkick_ids = (identity_values(identity, :songkick_ids) + [ids[:songkick_id]]).compact.map(&:to_s)

      Array(identities).select do |entry|
        next false unless identity_provider(entry) == 'musicbrainz'

        entry_ids = normalized_identifiers(identity_identifiers(entry))
        mbids.include?(entry_ids[:musicbrainz_id].to_s.downcase) ||
          (qid.present? && entry_ids[:wikidata_id].to_s.upcase == qid) ||
          songkick_ids.include?(entry_ids[:songkick_id].to_s)
      end
    end

    def identity_names(identity)
      ([identity_value(identity, :name)] + Array(identity_value(identity, :aliases))).compact
    end

    def identity_identifiers(identity)
      value = identity_value(identity, :identifiers)
      value.respond_to?(:to_h) ? value.to_h : {}
    end

    def identity_provider(identity)
      identity_value(identity, :provider).to_s
    end

    def identity_values(identity, key)
      direct = identity_value(identity, key)
      evidence = identity_value(identity, :evidence)
      nested = evidence.respond_to?(:to_h) ? (evidence.to_h[key] || evidence.to_h[key.to_s]) : nil
      (Array(direct) + Array(nested)).compact
    end

    def identity_value(identity, key)
      return unless identity.respond_to?(:to_h)

      identity.to_h[key] || identity.to_h[key.to_s]
    end

    def normalized_identifiers(raw)
      raw.to_h.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value if value.present?
      end.slice(:songkick_id, :musicbrainz_id, :wikidata_id)
    end

    def identifier_conflict?(expected, values)
      return false if expected.blank? || values.empty?

      !values.include?(expected.to_s)
    end

    def musical_entity?(identity)
      evidence = identity_value(identity, :evidence)
      explicit = evidence.respond_to?(:to_h) && (evidence.to_h[:musical_entity] || evidence.to_h['musical_entity'])
      explicit || (Array(identity_value(identity, :types)) + Array(identity_value(identity, :descriptions))).any? do |value|
        value.to_s.match?(Providers::Wikidata::MUSICAL_DESCRIPTION)
      end
    end

    def country_match?(artist, identity)
      return false if artist.country.blank?

      expected = canonical(artist.country)
      ([identity_value(identity, :country)] + Array(identity_value(identity, :countries))).compact.any? { |value| canonical(value) == expected }
    end

    def genre_match?(artist, identity)
      expected = Array(artist.genres).map { |value| canonical(value) }.reject(&:blank?)
      actual = Array(identity_value(identity, :genres)).map { |value| canonical(value) }.reject(&:blank?)
      expected.any? && (expected & actual).any?
    end

    def official_url_match?(artist, identity)
      expected = Array(artist.official_urls).filter_map { |url| url_host(url) }
      actual = Array(identity_value(identity, :official_urls)).filter_map { |url| url_host(url) }
      expected.any? && (expected & actual).any?
    end

    def url_host(url)
      URI.parse(url.to_s).host.to_s.downcase.sub(/\Awww\./, '').presence
    rescue URI::InvalidURIError
      nil
    end

    def equivalent_name?(left, right)
      canonical(left).present? && canonical(left) == canonical(right)
    end

    def canonical(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
    end

    def identity_key(identifiers, candidate)
      identifiers[:wikidata_id].presence || identifiers[:musicbrainz_id].presence || identifiers[:songkick_id].presence || candidate.image_url
    end

    def rejected(candidate, identifiers, reason)
      {
        candidate: candidate,
        identity_key: identity_key(identifiers, candidate),
        identifiers: identifiers,
        score: 0,
        signals: [],
        definitive: false,
        safe: false,
        plausible: reason != 'name_mismatch',
        rejection: reason
      }
    end

    def deduplicate_identities(ranked)
      ranked.group_by { |entry| entry[:identity_key] }.values.map { |entries| entries.max_by { |entry| entry[:score] } }
    end

    def ambiguous_result(ranked, reason)
      MatchResult.new(
        status: 'ambiguous',
        confidence: ranked.first&.dig(:score).to_i,
        identifiers: {},
        evidence: match_evidence(ranked).merge(ambiguity_reason: reason)
      )
    end

    def match_evidence(ranked)
      {
        threshold: ACCEPTANCE_SCORE,
        minimum_structured_signals: MIN_STRUCTURED_SIGNALS,
        ambiguity_margin: AMBIGUITY_MARGIN,
        ranked_candidates: ranked.first(10).map do |entry|
          {
            provider: entry[:candidate].provider,
            page_url: entry[:candidate].page_url,
            identity_key: entry[:identity_key],
            identifiers: entry[:identifiers],
            score: entry[:score],
            signals: entry[:signals],
            safe: entry[:safe],
            rejection: entry[:rejection]
          }.compact
        end
      }
    end
  end
end
