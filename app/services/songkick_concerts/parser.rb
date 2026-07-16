require 'json'
require 'nokogiri'
require 'uri'

module SongkickConcerts
  class Parser
    ImageCandidate = Struct.new(:url, :source, :score, :order, :page_url, :evidence, keyword_init: true)

    METADATA_IMAGE_SELECTORS = [
      ['meta[property="og:image:secure_url"][content]', 'content', 'open_graph_secure', 108],
      ['meta[property="og:image"][content]', 'content', 'open_graph', 106],
      ['meta[name="twitter:image"][content]', 'content', 'twitter', 100],
      ['meta[name="twitter:image:src"][content]', 'content', 'twitter', 100]
    ].freeze
    LAZY_IMAGE_ATTRIBUTES = [
      ['data-src', 'lazy_data_src', 86],
      ['data-lazy-src', 'lazy_data_lazy_src', 85],
      ['data-original', 'lazy_data_original', 84],
      ['src', 'image_src', 70]
    ].freeze

    def parse_listing(html, base_url: SongkickConcerts::Client::BASE_URL)
      music_event_nodes(html).map { |node| normalize_source_url(node, base_url) }
                             .uniq { |node| node['url'].presence || node['@id'] || node['name'] }
    end

    def next_page?(html)
      document = Nokogiri::HTML(html.to_s)
      document.at_css('.pagination a.next_page[href], .pagination a[rel="next"][href]').present?
    end

    def page_image_urls(html, base_url: SongkickConcerts::Client::BASE_URL, artist_names: [], source_artist_ids: [])
      page_image_candidates(
        html,
        base_url: base_url,
        artist_names: artist_names,
        source_artist_ids: source_artist_ids
      ).map(&:url)
    end

    def page_image_candidates(html, base_url: SongkickConcerts::Client::BASE_URL, artist_names: [], source_artist_ids: [])
      document = Nokogiri::HTML(html.to_s)
      event_nodes = music_event_nodes_from_document(document)
      performer_names = (performer_names_from(event_nodes) + Array(artist_names).map(&:to_s)).reject(&:blank?).uniq
      candidates = []

      event_nodes.each do |event_node|
        add_image_values(
          candidates,
          event_node['image'],
          base_url: base_url,
          source: 'json_ld_event',
          score: 120,
          hint: event_node['name']
        )
        performer_nodes(event_node['performer']).each do |performer|
          add_image_values(
            candidates,
            performer['image'] || performer[:image],
            base_url: base_url,
            source: 'json_ld_performer',
            score: 115,
            hint: performer['name'] || performer[:name]
          )
        end
      end

      METADATA_IMAGE_SELECTORS.each do |selector, attribute, source, score|
        document.css(selector).each do |node|
          add_candidate(candidates, node[attribute], base_url: base_url, source: source, score: score)
        end
      end

      document.css('link[rel~="image_src"][href]').each do |node|
        add_candidate(candidates, node['href'], base_url: base_url, source: 'image_src_link', score: 102)
      end

      document.css('img, source').each do |node|
        hint = image_hint(node)
        semantics = semantic_score(hint, performer_names)

        %w[srcset data-srcset].each do |attribute|
          ImageUrlNormalizer.srcset_entries(node[attribute], base_url: base_url).each do |entry|
            add_candidate(
              candidates,
              entry[:url],
              base_url: base_url,
              source: attribute,
              score: 92 + semantics + entry[:score],
              hint: hint
            )
          end
        end

        next unless node.name == 'img'

        LAZY_IMAGE_ATTRIBUTES.each do |attribute, source, score|
          add_candidate(
            candidates,
            node[attribute],
            base_url: base_url,
            source: source,
            score: score + semantics,
            hint: hint
          )
        end
      end

      ranked_candidates(candidates, source_artist_ids: source_artist_ids)
    end

    def placeholder_image_url?(value)
      ImageUrlNormalizer.placeholder?(value)
    end

    private

    def music_event_nodes(html)
      document = Nokogiri::HTML(html.to_s)
      music_event_nodes_from_document(document)
    end

    def music_event_nodes_from_document(document)
      document.css('script[type="application/ld+json"]').flat_map do |script|
        parse_json_ld(script.text)
      end.select { |node| supported_event_node?(node) }
    end

    def parse_json_ld(raw_json)
      parsed = JSON.parse(raw_json.to_s)
      extract_nodes(parsed)
    rescue JSON::ParserError
      []
    end

    def extract_nodes(value)
      case value
      when Array
        value.flat_map { |entry| extract_nodes(entry) }
      when Hash
        graph = value['@graph']
        graph.present? ? extract_nodes(graph) : [value]
      else
        []
      end
    end

    def supported_event_node?(node)
      types = Array(node['@type']).map(&:to_s)
      types.include?('MusicEvent') || types.include?('MusicFestival')
    end

    def normalize_source_url(node, base_url)
      node = node.deep_dup
      source_url = node['url'].presence || node['@id'].to_s.sub(/#event\z/, '').presence
      node['url'] = ImageUrlNormalizer.normalize(source_url, base_url: base_url) if source_url.present?
      image_base_url = node['url'].presence || base_url
      image_candidates = ImageUrlNormalizer.extract(json_ld_image_values(node), base_url: image_base_url)
      node['image_candidates'] = image_candidates if image_candidates.any?
      if node['image'].is_a?(String)
        node['image'] = ImageUrlNormalizer.normalize(node['image'], base_url: image_base_url) || node['image']
      end
      node
    rescue URI::InvalidURIError
      node
    end

    def json_ld_image_values(node)
      [node['image']] + performer_nodes(node['performer']).map { |performer| performer['image'] || performer[:image] }
    end

    def performer_nodes(value)
      entries = value.is_a?(Array) ? value : [value]
      entries.select { |entry| entry.is_a?(Hash) }
    end

    def performer_names_from(event_nodes)
      event_nodes.flat_map do |event_node|
        performer_nodes(event_node['performer']).filter_map { |performer| performer['name'].to_s.squish.presence }
      end.uniq
    end

    def add_image_values(candidates, value, base_url:, source:, score:, hint: nil)
      ImageUrlNormalizer.extract(value, base_url: base_url).each do |url|
        add_candidate(candidates, url, base_url: base_url, source: source, score: score, hint: hint)
      end
    end

    def add_candidate(candidates, value, base_url:, source:, score:, hint: nil)
      url = ImageUrlNormalizer.normalize(value, base_url: base_url)
      return if url.blank? || ImageUrlNormalizer.placeholder?(url, hint: hint)

      candidates << ImageCandidate.new(
        url: url,
        source: source,
        score: score.to_i + ImageUrlNormalizer.quality_score(url),
        order: candidates.length,
        page_url: base_url,
        evidence: { extraction_source: source, extraction_hint: hint.to_s.squish.presence }.compact
      )
    end

    def ranked_candidates(candidates, source_artist_ids: [])
      artist_ids = Array(source_artist_ids).map(&:to_s).reject(&:blank?).uniq
      candidates.each do |candidate|
        candidate.score += 15 if artist_ids.any? { |artist_id| candidate_matches_artist_id?(candidate, artist_id) }
      end

      candidates.group_by(&:url).values.map do |duplicates|
        duplicates.max_by { |candidate| [candidate.score, -candidate.order] }
      end.sort_by { |candidate| [-candidate.score, candidate.order] }
    end

    def candidate_matches_artist_id?(candidate, artist_id)
      path = URI.parse(candidate.url).path.to_s
      return path.split(/\D+/).include?(artist_id) if artist_id.match?(/\A\d+\z/)

      path.downcase.include?(artist_id.downcase)
    rescue URI::InvalidURIError
      false
    end

    def image_hint(node)
      values = %w[class id alt title role].filter_map { |attribute| node[attribute].to_s.strip.presence }
      values.concat(parent_image_hint(node))
      values.join(' ').squish
    end

    def parent_image_hint(node)
      parent = node.parent
      values = []
      values << parent['class'] if parent&.element?
      values << parent['id'] if parent&.element?

      picture = node.ancestors.find { |ancestor| ancestor.name == 'picture' }
      related_image = picture&.at_css('img')
      if related_image && related_image != node
        values.concat(%w[class id alt title].map { |attribute| related_image[attribute] })
      end
      values.compact
    end

    def semantic_score(hint, performer_names)
      normalized_hint = canonical_text(hint)
      score = 0
      score += 45 if normalized_hint.match?(/\bevent hero\b|\bconcert hero\b/)
      score += 32 if normalized_hint.match?(/\bheadliner\b|\bline up\b|\blineup\b/)
      score += 22 if normalized_hint.match?(/\bartist profile\b/)
      score += 12 if normalized_hint.match?(/\bartist\b|\bperformer\b/)
      score += 35 if performer_names.any? { |name| normalized_hint.include?(canonical_text(name)) }
      score -= 35 if normalized_hint.match?(/\bvenue\b|\brecinto\b/)
      score -= 25 if normalized_hint.match?(/\bnavigation\b|\brelated\b|\brecommended\b/)
      score
    end

    def canonical_text(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
    end
  end
end
