require 'net/http'
require 'rack/utils'
require 'uri'

module SongkickConcerts
  class Client
    class RequestError < StandardError; end
    class RobotsBlockedError < RequestError; end

    BASE_URL = 'https://www.songkick.com'.freeze
    DEFAULT_USER_AGENT = 'ToppinBlackCoffeeConcertImporter/1.0 (+https://toppinapp.com)'.freeze
    DEFAULT_CRAWL_DELAY_SECONDS = 10.0
    DEFAULT_TIMEOUT_SECONDS = 15

    attr_reader :robots_requests_count, :listing_requests_count

    def initialize(user_agent: DEFAULT_USER_AGENT, request_delay_seconds: DEFAULT_CRAWL_DELAY_SECONDS, timeout: DEFAULT_TIMEOUT_SECONDS)
      @user_agent = user_agent
      @requested_delay_seconds = request_delay_seconds.to_f
      @timeout = timeout
      @last_request_at = nil
      @robots_loaded = false
      @robots_disallowed_paths = []
      @robots_crawl_delay_seconds = DEFAULT_CRAWL_DELAY_SECONDS
      @robots_requests_count = 0
      @listing_requests_count = 0
    end

    def fetch_metro_page(source_path, page:)
      uri = absolute_uri(source_path)
      query_params = Rack::Utils.parse_nested_query(uri.query)
      query_params['page'] = page.to_i.to_s if page.to_i > 1
      uri.query = query_params.present? ? query_params.to_query : nil

      @listing_requests_count += 1
      get("#{uri.path}#{uri.query.present? ? "?#{uri.query}" : ''}")
    end

    def request_delay_seconds
      [@requested_delay_seconds, @robots_crawl_delay_seconds || DEFAULT_CRAWL_DELAY_SECONDS].compact.max
    end

    private

    def get(path)
      load_robots_rules!
      ensure_robots_allowed!(path)
      respect_delay!
      response = http_get(absolute_uri(path))
      @last_request_at = monotonic_time

      return response_body(response) if response.is_a?(Net::HTTPSuccess)

      raise RequestError, "Songkick respondio HTTP #{response.code} para #{path}"
    end

    def load_robots_rules!
      return if @robots_loaded

      response = http_get(URI.join(BASE_URL, '/robots.txt'))
      @robots_requests_count += 1
      @last_request_at = monotonic_time
      parse_robots(response_body(response)) if response.is_a?(Net::HTTPSuccess)
      @robots_loaded = true
    end

    def parse_robots(body)
      active_for_all = false

      body.each_line do |line|
        stripped = line.split('#', 2).first.to_s.strip
        next if stripped.blank?

        key, value = stripped.split(':', 2).map { |part| part.to_s.strip }
        case key.downcase
        when 'user-agent'
          active_for_all = value == '*'
        when 'disallow'
          @robots_disallowed_paths << value if active_for_all && value.present?
        when 'crawl-delay'
          @robots_crawl_delay_seconds = value.to_f if active_for_all && value.to_f.positive?
        end
      end
    end

    def ensure_robots_allowed!(path)
      request_path = absolute_uri(path).path
      blocked_path = @robots_disallowed_paths.find do |disallowed|
        next false if disallowed.blank?

        request_path.start_with?(disallowed)
      end
      return unless blocked_path

      raise RobotsBlockedError, "robots.txt bloquea #{request_path} por regla #{blocked_path}"
    end

    def respect_delay!
      return unless @last_request_at

      remaining = request_delay_seconds - (monotonic_time - @last_request_at)
      sleep(remaining) if remaining.positive?
    end

    def http_get(uri)
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = @user_agent
      request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      request['Accept-Language'] = 'en,es;q=0.9'

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @timeout, read_timeout: @timeout) do |http|
        http.request(request)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise RequestError, "No se pudo pedir #{uri}: #{e.class} - #{e.message}"
    end

    def response_body(response)
      body = response.body.to_s
      charset = response_charset(response)
      body.force_encoding(charset)
      body.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    rescue Encoding::ConverterNotFoundError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      response.body.to_s.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end

    def response_charset(response)
      content_type = response['content-type'].to_s
      content_type[/charset=([^;\s]+)/i, 1].presence || 'UTF-8'
    end

    def absolute_uri(path_or_url)
      uri = URI.parse(path_or_url.to_s)
      uri = URI.join(BASE_URL, path_or_url.to_s) unless uri.host
      raise RequestError, 'La URL no pertenece a Songkick.' unless songkick_host?(uri.host)

      uri
    rescue URI::InvalidURIError => e
      raise RequestError, "URL Songkick invalida: #{e.message}"
    end

    def songkick_host?(host)
      host.to_s.downcase.sub(/\Awww\./, '') == 'songkick.com'
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
