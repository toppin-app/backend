require 'ipaddr'
require 'json'
require 'net/http'
require 'resolv'
require 'set'
require 'uri'

module BlackCoffeeConcertCoverSearch
  class HttpClient
    DEFAULT_ALLOWED_HOSTS = %w[
      musicbrainz.org
      www.wikidata.org
      wikidata.org
      commons.wikimedia.org
    ].freeze
    DEFAULT_USER_AGENT = 'ToppinConcertCoverSearch/1.0 (+https://toppinapp.com)'.freeze
    DEFAULT_OPEN_TIMEOUT = 4
    DEFAULT_READ_TIMEOUT = 8
    DEFAULT_MAX_REDIRECTS = 3
    DEFAULT_MAX_BODY_BYTES = 2.megabytes
    RETRYABLE_STATUSES = [408, 425, 429].freeze
    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
      169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
      192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
      224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 2001:db8::/32
      fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    Response = Struct.new(
      :status,
      :json,
      :http_status,
      :final_url,
      :retry_after,
      :error_type,
      :error_message,
      keyword_init: true
    ) do
      def ok?
        status == 'ok'
      end

      def retryable?
        status == 'retryable_error'
      end
    end

    attr_reader :requests_count

    def initialize(
      allowed_hosts: DEFAULT_ALLOWED_HOSTS,
      user_agent: ENV.fetch('CONCERT_COVER_SEARCH_USER_AGENT', DEFAULT_USER_AGENT),
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      read_timeout: DEFAULT_READ_TIMEOUT,
      max_redirects: DEFAULT_MAX_REDIRECTS,
      max_body_bytes: DEFAULT_MAX_BODY_BYTES,
      address_resolver: ->(host) { Resolv.getaddresses(host) },
      http_factory: nil
    )
      @allowed_hosts = Array(allowed_hosts).map { |host| host.to_s.downcase }.to_set
      @user_agent = user_agent.to_s
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_redirects = max_redirects.to_i
      @max_body_bytes = max_body_bytes.to_i
      @address_resolver = address_resolver
      @http_factory = http_factory || method(:build_http)
      @requests_count = 0
    end

    def get(url, params: {})
      uri = URI.parse(url.to_s)
      uri.query = merged_query(uri.query, params)
      request(uri)
    rescue URI::InvalidURIError => e
      failure('unavailable', 'invalid_url', e.message)
    end

    private

    attr_reader :allowed_hosts, :user_agent, :open_timeout, :read_timeout,
                :max_redirects, :max_body_bytes, :address_resolver, :http_factory

    def request(uri, redirects = 0)
      validation = validate_uri(uri)
      return validation if validation

      public_address = public_address_for(uri.host)
      return public_address if public_address.is_a?(Response)

      @requests_count += 1
      http_request = Net::HTTP::Get.new(uri)
      http_request['User-Agent'] = user_agent
      http_request['Accept'] = 'application/json'
      http_request['Accept-Encoding'] = 'identity'

      result = nil
      http_factory.call(uri, public_address).start do |http|
        http.request(http_request) do |response|
          code = response.code.to_i
          if code.between?(300, 399)
            return failure('unavailable', 'too_many_redirects', "La API redirige mas de #{max_redirects} veces.", code) if redirects >= max_redirects

            location = response['location'].to_s
            return failure('unavailable', 'redirect_without_location', 'La redireccion no incluye destino.', code) if location.blank?

            return request(URI.join(uri, location), redirects + 1)
          end

          return transient_http_failure(response, code) if retryable_status?(code)
          return failure('not_found', 'not_found', "La API responde HTTP #{code}.", code) if [404, 410].include?(code)
          return failure('unavailable', 'access_denied', "La API responde HTTP #{code}.", code) if [401, 403].include?(code)
          return failure('unavailable', 'http_error', "La API responde HTTP #{code}.", code) unless code == 200

          body = read_body(response)
          return body if body.is_a?(Response)

          parsed = JSON.parse(body)
          if parsed.is_a?(Hash) && parsed['error'].is_a?(Hash)
            return api_error(parsed['error'], response)
          end

          result = Response.new(status: 'ok', json: parsed, http_status: code, final_url: uri.to_s)
        end
      end
      result || failure('retryable_error', 'empty_response', 'La API no devolvio una respuesta.', nil)
    rescue JSON::ParserError => e
      failure('unavailable', 'invalid_json', "La API no devolvio JSON valido: #{e.message}")
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      failure('retryable_error', 'timeout', e.message)
    rescue SocketError, SystemCallError, Resolv::ResolvError => e
      failure('retryable_error', 'network_error', e.message)
    rescue StandardError => e
      failure('retryable_error', 'unexpected_http_error', "#{e.class}: #{e.message}")
    end

    def validate_uri(uri)
      unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.blank?
        return failure('unavailable', 'invalid_url', 'La API debe usar HTTPS, incluir host y no incluir credenciales.')
      end
      return if allowed_hosts.include?(uri.host.to_s.downcase)

      failure('unavailable', 'blocked_host', "Host de API no permitido: #{uri.host}")
    end

    def public_address_for(host)
      addresses = Array(address_resolver.call(host)).filter_map do |raw_address|
        address = IPAddr.new(raw_address)
        address.ipv4_mapped? ? address.native : address
      rescue IPAddr::InvalidAddressError
        nil
      end
      return failure('retryable_error', 'dns_error', 'No se pudo resolver el host de la API.') if addresses.empty?
      return failure('unavailable', 'blocked_destination', 'El host de la API resuelve a una red privada o reservada.') if addresses.any? { |address| blocked_address?(address) }

      addresses.first.to_s
    end

    def blocked_address?(address)
      BLOCKED_NETWORKS.any? { |network| network.include?(address) }
    end

    def build_http(uri, public_address)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = public_address
      http.use_ssl = true
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http
    end

    def merged_query(existing_query, params)
      existing = URI.decode_www_form(existing_query.to_s)
      supplied = params.to_h.flat_map do |key, value|
        Array(value).map { |entry| [key.to_s, entry.to_s] }
      end
      URI.encode_www_form(existing + supplied)
    end

    def read_body(response)
      body = +''
      response.read_body do |chunk|
        body << chunk
        return failure('unavailable', 'response_too_large', "La respuesta supera #{max_body_bytes} bytes.", response.code.to_i) if body.bytesize > max_body_bytes
      end
      return failure('retryable_error', 'empty_response', 'La API devolvio un cuerpo vacio.', response.code.to_i) if body.blank?

      body
    end

    def retryable_status?(code)
      RETRYABLE_STATUSES.include?(code) || code >= 500
    end

    def transient_http_failure(response, code)
      error_type = if code == 429
                     'rate_limited'
                   elsif code == 408
                     'timeout'
                   elsif code == 425
                     'upstream_not_ready'
                   else
                     'upstream_server_error'
                   end
      result = failure('retryable_error', error_type, "La API responde HTTP #{code}.", code)
      result.retry_after = retry_after_seconds(response['retry-after'])
      result
    end

    def api_error(error, response)
      code = error['code'].to_s
      message = error['info'].to_s.presence || "Error de API: #{code}"
      if %w[maxlag ratelimited readonly].include?(code)
        result = failure('retryable_error', code, message, response.code.to_i)
        result.retry_after = retry_after_seconds(response['retry-after'])
        return result
      end

      failure('unavailable', "api_#{code.presence || 'error'}", message, response.code.to_i)
    end

    def retry_after_seconds(value)
      Integer(value, exception: false)
    end

    def failure(status, error_type, message, http_status = nil)
      Response.new(
        status: status,
        http_status: http_status,
        error_type: error_type,
        error_message: message
      )
    end
  end
end
