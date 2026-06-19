require 'json'
require 'nokogiri'
require 'uri'
require 'cgi'

module FanMusicFest
  class Parser
    SPAIN_BOUNDS = {
      latitude: (27.0..44.5),
      longitude: (-19.0..5.0)
    }.freeze

    def parse_listing(html, base_url: FanMusicFest::Client::BASE_URL)
      festival_nodes(html).map { |node| normalize_source_url(node, base_url) }.uniq { |node| node['url'].presence || node['@id'] }
    end

    def parse_detail(html, source_url:)
      document = Nokogiri::HTML(html.to_s)
      node = festival_nodes(html).first
      return {} if node.blank?

      normalized_node = normalize_source_url(node, source_url)
      normalized_node['_fanmusicfest_detail'] = {
        'coordinates' => extract_map_coordinates_from_festival_detail(document, normalized_node),
        'source_description' => extract_source_description(document, normalized_node),
        'official_url' => extract_official_url(document),
        'ticket_url' => extract_ticket_url(document),
        'ticket_price_text' => extract_ticket_price_text(document),
        'raw_location_text' => extract_raw_location_text(document)
      }.compact
      normalized_node
    end

    def extract_map_coordinates_from_festival_detail(html_or_document, festival_node = nil)
      document = html_or_document.is_a?(Nokogiri::HTML::Document) ? html_or_document : Nokogiri::HTML(html_or_document.to_s)
      node = festival_node || festival_nodes(document.to_html).first || {}
      candidates = [
        schema_coordinates(node),
        data_attribute_coordinates(document),
        open_graph_coordinates(document),
        map_link_coordinates(document),
        inline_script_coordinates(document)
      ].compact

      candidate = candidates.find { |entry| valid_coordinates?(entry['latitude'], entry['longitude']) }
      return candidate if candidate

      invalid_candidate = candidates.first
      return { 'confidence' => 'none', 'warning' => 'No se encontraron coordenadas validas.' } unless invalid_candidate

      {
        'confidence' => 'none',
        'source' => invalid_candidate['source'],
        'warning' => 'Las coordenadas encontradas estan fuera de los limites admitidos para Espana.'
      }
    end

    private

    def festival_nodes(html)
      document = Nokogiri::HTML(html.to_s)
      document.css('script[type="application/ld+json"]').flat_map do |script|
        parse_json_ld(script.text)
      end.select { |node| festival_node?(node) }
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

    def festival_node?(node)
      Array(node['@type']).map(&:to_s).include?('Festival')
    end

    def normalize_source_url(node, base_url)
      node = node.deep_dup
      source_url = node['url'].presence || node['@id'].to_s.sub(/#event\z/, '').presence
      node['url'] = URI.join(base_url, source_url).to_s if source_url.present?
      node
    rescue URI::InvalidURIError
      node
    end

    def schema_coordinates(node)
      geo = node.dig('location', 'geo')
      return nil unless geo.is_a?(Hash)

      coordinate_payload(
        geo['latitude'],
        geo['longitude'],
        source: 'schema_org',
        confidence: 'high'
      )
    end

    def data_attribute_coordinates(document)
      element = document.at_css(
        '[data-latitude][data-longitude], [data-lat][data-lng], [data-latitude][data-lng], [data-lat][data-longitude]'
      )
      return nil unless element

      coordinate_payload(
        element['data-latitude'].presence || element['data-lat'],
        element['data-longitude'].presence || element['data-lng'],
        source: 'fanmusicfest_map',
        confidence: 'high'
      )
    end

    def open_graph_coordinates(document)
      latitude = document.at_css('meta[property="og:latitude"]')&.[]('content')
      longitude = document.at_css('meta[property="og:longitude"]')&.[]('content')
      return nil if latitude.blank? || longitude.blank?

      coordinate_payload(latitude, longitude, source: 'open_graph', confidence: 'high')
    end

    def map_link_coordinates(document)
      document.css('a[href], iframe[src]').each do |element|
        uri = safe_uri(element['href'].presence || element['src'])
        next unless uri

        params = CGI.parse(uri.query.to_s)
        latitude = params['center.lat']&.first || params['lat']&.first || params['latitude']&.first
        longitude = params['center.lng']&.first || params['lng']&.first || params['longitude']&.first
        if latitude.blank? || longitude.blank?
          pair = coordinate_pair_from_text(
            params.values.flatten.find { |value| coordinate_pair_from_text(value) }.presence ||
            uri.path
          )
          latitude, longitude = pair if pair
        end
        next if latitude.blank? || longitude.blank?

        return coordinate_payload(
          latitude,
          longitude,
          source: 'map_link',
          confidence: 'medium',
          map_source_url: uri.to_s
        )
      end
      nil
    end

    def inline_script_coordinates(document)
      document.css('script:not([type="application/ld+json"])').each do |script|
        latitude = script.text.match(/(?:latitude|lat)\s*[:=]\s*["']?(-?\d{1,2}(?:\.\d+)?)/i)&.captures&.first
        longitude = script.text.match(/(?:longitude|lng|lon)\s*[:=]\s*["']?(-?\d{1,3}(?:\.\d+)?)/i)&.captures&.first
        next if latitude.blank? || longitude.blank?

        return coordinate_payload(
          latitude,
          longitude,
          source: 'inline_script',
          confidence: 'low'
        )
      end
      nil
    end

    def coordinate_pair_from_text(value)
      match = value.to_s.match(/(?:@|q=|query=|ll=|center=)?\s*(-?\d{1,2}(?:\.\d+)?)\s*(?:,|%2C|\|)\s*(-?\d{1,3}(?:\.\d+)?)/i)
      match ? match.captures : nil
    end

    def coordinate_payload(latitude, longitude, source:, confidence:, map_source_url: nil)
      {
        'latitude' => Float(latitude),
        'longitude' => Float(longitude),
        'source' => source,
        'confidence' => confidence,
        'map_source_url' => map_source_url
      }.compact
    rescue ArgumentError, TypeError
      nil
    end

    def valid_coordinates?(latitude, longitude)
      latitude.is_a?(Numeric) &&
        longitude.is_a?(Numeric) &&
        latitude.finite? &&
        longitude.finite? &&
        latitude.between?(-90, 90) &&
        longitude.between?(-180, 180) &&
        SPAIN_BOUNDS[:latitude].cover?(latitude) &&
        SPAIN_BOUNDS[:longitude].cover?(longitude)
    end

    def extract_source_description(document, node)
      description = node['description'].presence || document.at_css('.node__desc .contenido-desc')&.text
      clean_source_text(description)
    end

    def clean_source_text(value)
      text = ActionController::Base.helpers.strip_tags(value.to_s).squish
      return nil if text.length < 40
      return nil if text.match?(/cookies|pol[ií]tica de privacidad|publicidad/i)

      text.first(2_000)
    end

    def extract_official_url(document)
      popover_links(document).find do |url|
        uri = safe_uri(url)
        uri && !fan_music_fest_host?(uri.host) && !social_host?(uri.host)
      end
    end

    def popover_links(document)
      document.css('[data-content]').flat_map do |element|
        fragment = Nokogiri::HTML.fragment(element['data-content'].to_s)
        fragment.css('a[href]').filter_map { |link| safe_http_url(link['href']) }
      end.uniq
    end

    def extract_ticket_url(document)
      selector = '#block-views-fmf-festivales-block-entradas a[href]'
      document.css(selector).filter_map { |link| safe_http_url(link['href']) }
              .find { |url| !fan_music_fest_host?(safe_uri(url)&.host) }
    end

    def extract_ticket_price_text(document)
      text = document.at_css('#block-views-fmf-festivales-block-entradas .card__precio')&.text.to_s.squish
      text.presence
    end

    def extract_raw_location_text(document)
      ActionController::Base.helpers.strip_tags(document.at_css('.node__ubicacion')&.text.to_s).squish.presence
    end

    def safe_http_url(value)
      uri = safe_uri(value)
      return nil unless uri && %w[http https].include?(uri.scheme) && uri.host.present?

      uri.to_s
    end

    def safe_uri(value)
      URI.parse(value.to_s)
    rescue URI::InvalidURIError
      nil
    end

    def fan_music_fest_host?(host)
      host.to_s.downcase.sub(/\Awww\./, '') == 'fanmusicfest.com'
    end

    def social_host?(host)
      normalized = host.to_s.downcase.sub(/\Awww\./, '')
      %w[instagram.com facebook.com x.com twitter.com tiktok.com youtube.com].include?(normalized)
    end
  end
end
