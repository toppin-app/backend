require 'net/http'
require 'uri'

module FanMusicFest
  class Client
    class RequestError < StandardError; end
    class RobotsBlockedError < RequestError; end

    BASE_URL = 'https://fanmusicfest.com'.freeze
    CALENDAR_PATH = '/calendario-festivales'.freeze
    DEFAULT_USER_AGENT = 'ToppinBlackCoffeeFestivalImporter/1.0 (+https://toppinapp.com)'.freeze
    DEFAULT_CRAWL_DELAY_SECONDS = 10.0
    DEFAULT_TIMEOUT_SECONDS = 15

    attr_reader :robots_requests_count, :listing_requests_count, :detail_requests_count

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
      @detail_requests_count = 0
    end

    def fetch_calendar_page(page:)
      page_index = page.to_i
      path = CALENDAR_PATH
      path = "#{path}?page=#{page_index}" if page_index.positive?
      @listing_requests_count += 1
      get(path)
    end

    def fetch_detail(url)
      uri = absolute_uri(url)
      raise RequestError, 'La URL de detalle no pertenece a FanMusicFest.' unless uri.host == URI(BASE_URL).host

      @detail_requests_count += 1
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

      return response.body if response.is_a?(Net::HTTPSuccess)

      raise RequestError, "FanMusicFest respondio HTTP #{response.code} para #{path}"
    end

    def load_robots_rules!
      return if @robots_loaded

      response = http_get(URI.join(BASE_URL, '/robots.txt'))
      @robots_requests_count += 1
      @last_request_at = monotonic_time
      parse_robots(response.body.to_s) if response.is_a?(Net::HTTPSuccess)
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
      blocked_path = @robots_disallowed_paths.find { |disallowed| request_path.start_with?(disallowed) }
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

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @timeout, read_timeout: @timeout) do |http|
        http.request(request)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise RequestError, "No se pudo pedir #{uri}: #{e.class} - #{e.message}"
    end

    def absolute_uri(path_or_url)
      URI.join(BASE_URL, path_or_url.to_s)
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
