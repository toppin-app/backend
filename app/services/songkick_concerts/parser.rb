require 'json'
require 'nokogiri'
require 'uri'

module SongkickConcerts
  class Parser
    def parse_listing(html, base_url: SongkickConcerts::Client::BASE_URL)
      music_event_nodes(html).map { |node| normalize_source_url(node, base_url) }
                             .uniq { |node| node['url'].presence || node['@id'] || node['name'] }
    end

    def next_page?(html)
      document = Nokogiri::HTML(html.to_s)
      document.at_css('.pagination a.next_page[href], .pagination a[rel="next"][href]').present?
    end

    private

    def music_event_nodes(html)
      document = Nokogiri::HTML(html.to_s)
      document.css('script[type="application/ld+json"]').flat_map do |script|
        parse_json_ld(script.text)
      end.select { |node| music_event_node?(node) }
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

    def music_event_node?(node)
      Array(node['@type']).map(&:to_s).include?('MusicEvent')
    end

    def normalize_source_url(node, base_url)
      node = node.deep_dup
      source_url = node['url'].presence || node['@id'].to_s.sub(/#event\z/, '').presence
      node['url'] = URI.join(base_url, source_url).to_s if source_url.present?
      node
    rescue URI::InvalidURIError
      node
    end
  end
end
