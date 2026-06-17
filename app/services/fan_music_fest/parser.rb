require 'json'
require 'nokogiri'
require 'uri'

module FanMusicFest
  class Parser
    def parse_listing(html, base_url: FanMusicFest::Client::BASE_URL)
      festival_nodes(html).map { |node| normalize_source_url(node, base_url) }.uniq { |node| node['url'].presence || node['@id'] }
    end

    def parse_detail(html, source_url:)
      node = festival_nodes(html).first
      return {} if node.blank?

      normalize_source_url(node, source_url)
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
  end
end
