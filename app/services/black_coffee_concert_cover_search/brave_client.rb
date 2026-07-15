require 'json'
require 'net/http'
require 'uri'

module BlackCoffeeConcertCoverSearch
  class BraveClient
    class RequestError < StandardError; end

    SearchResult = Struct.new(
      :title,
      :description,
      :image_url,
      :page_url,
      :width,
      :height,
      :publisher,
      keyword_init: true
    )

    ENDPOINT = 'https://api.search.brave.com/res/v1/images/search'.freeze
    DEFAULT_RESULT_COUNT = 10
    USER_AGENT = 'Toppin Black Coffee Concert Cover Search/1.0'.freeze

    attr_reader :requests_count

    def self.configured?
      ENV['BRAVE_SEARCH_API_KEY'].to_s.strip.present?
    end

    def initialize(api_key: ENV['BRAVE_SEARCH_API_KEY'], timeout: 10)
      @api_key = api_key.to_s.strip
      @timeout = timeout
      @requests_count = 0
    end

    def configured?
      api_key.present?
    end

    def search(query, count: DEFAULT_RESULT_COUNT)
      return [] unless configured?

      uri = URI.parse(ENDPOINT)
      uri.query = URI.encode_www_form(
        q: query,
        count: [[count.to_i, 1].max, 20].min,
        country: 'ES',
        search_lang: 'es',
        safesearch: 'strict'
      )
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/json'
      request['User-Agent'] = USER_AGENT
      request['X-Subscription-Token'] = api_key
      @requests_count += 1

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: timeout,
        read_timeout: timeout
      ) { |http| http.request(request) }
      raise RequestError, "Brave Image Search respondio HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parse_results(response.body)
    rescue JSON::ParserError => e
      raise RequestError, "Brave Image Search devolvio JSON invalido: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise RequestError, "No se pudo consultar Brave Image Search: #{e.class} - #{e.message}"
    end

    private

    attr_reader :api_key, :timeout

    def parse_results(body)
      payload = JSON.parse(body.to_s)
      Array(payload['results']).filter_map do |entry|
        properties = entry['properties'].is_a?(Hash) ? entry['properties'] : {}
        thumbnail = entry['thumbnail'].is_a?(Hash) ? entry['thumbnail'] : {}
        image_url = safe_http_url(properties['url']) || safe_http_url(entry['image_url']) || safe_http_url(thumbnail['src'])
        next if image_url.blank?

        SearchResult.new(
          title: entry['title'].to_s,
          description: entry['description'].to_s,
          image_url: image_url,
          page_url: safe_http_url(entry['url']) || safe_http_url(entry['source']),
          width: positive_integer(properties['width'] || entry['width']),
          height: positive_integer(properties['height'] || entry['height']),
          publisher: publisher_name(entry['meta_url'])
        )
      end
    end

    def safe_http_url(value)
      uri = URI.parse(value.to_s)
      return nil unless %w[http https].include?(uri.scheme) && uri.host.present?

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def positive_integer(value)
      integer = value.to_i
      integer.positive? ? integer : nil
    end

    def publisher_name(value)
      return value['hostname'].to_s if value.is_a?(Hash)

      value.to_s
    end
  end
end
