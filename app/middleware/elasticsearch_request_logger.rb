require 'elasticsearch'
require 'json'

class ElasticsearchRequestLogger
  def initialize(app)
    @app = app
    @elasticsearch_client = nil
    setup_elasticsearch_client
  end

  def call(env)
    start_time = Time.current
    request = Rack::Request.new(env)

    status, headers, response = @app.call(env)

    end_time = Time.current
    duration = ((end_time - start_time) * 1000).round(2)

    log_request(request, status, duration, start_time)

    [status, headers, response]
  rescue => e
    end_time = Time.current
    duration = ((end_time - start_time) * 1000).round(2)
    log_request(request, 500, duration, start_time, e.message)
    raise e
  end

  private

  def setup_elasticsearch_client
    return unless elasticsearch_enabled?

    @elasticsearch_client = Elasticsearch::Client.new(
      url: ENV.fetch('ELASTICSEARCH_URL', 'https://web-elasticsearch-logs.uao3jo.easypanel.host:443'),
      user: ENV.fetch('ELASTICSEARCH_USER', 'elastic'),
      password: ENV.fetch('ELASTICSEARCH_PASSWORD', 'elasticsearch-logs'),
      transport_options: {
        request: { timeout: 5 },
        ssl: { verify: false }
      }
    )

    Rails.logger.info "✅ Elasticsearch middleware initialized successfully"
  rescue => e
    Rails.logger.error "❌ Failed to initialize Elasticsearch client: #{e.message}"
    @elasticsearch_client = nil
  end

  def elasticsearch_enabled?
    ENV['ENABLE_ELASTICSEARCH_LOGGING'] == 'true'
  end

  def log_request(request, status, duration, timestamp, error = nil)
    return unless @elasticsearch_client

    begin
      location = get_manual_location(request.ip)

      log_entry = {
        '@timestamp' => timestamp.iso8601,
        'method' => request.request_method,
        'path' => request.path,
        'full_path' => request.fullpath,
        'query_string' => request.query_string,
        'status_code' => status,
        'duration_ms' => duration,
        'ip_address' => request.ip,
        'user_agent' => request.user_agent,
        'referer' => request.referer,
        'host' => request.host,
        'content_type' => request.content_type,
        'content_length' => request.content_length,
        'scheme' => request.scheme,
        'environment' => Rails.env,
        'application' => 'toppin-backend',
        'log_type' => 'http_request',
        'hostname' => Socket.gethostname
      }

      # Ubicación manual separada en campos compatibles con geo_point
      if location
        log_entry['manual_location'] = location[:location]        # geo_point (lat/lon)
        log_entry['manual_location_meta'] = location[:meta]       # detalles (ciudad, país)
      end

      # Headers importantes
      log_entry['headers'] = extract_important_headers(request)

      # Info de autenticación
      if request.env['HTTP_AUTHORIZATION']
        log_entry['has_auth'] = true
        log_entry['auth_type'] = request.env['HTTP_AUTHORIZATION'].split(' ').first
      end

      # Nivel de log
      log_entry['level'] = if error
                             'ERROR'
                           elsif status >= 400
                             'WARN'
                           else
                             'INFO'
                           end

      log_entry['error'] = error if error

      # 👉 Nuevo índice con mapping correcto
      index_name = "toppin-backend-logs-v2-#{Date.current.strftime('%Y.%m.%d')}"

      @elasticsearch_client.index(
        index: index_name,
        pipeline: 'geoip-pipeline',
        body: log_entry
      )

    rescue => e
      Rails.logger.error "Failed to log to Elasticsearch: #{e.message}"
      Rails.logger.info "#{request.request_method} #{request.fullpath} - #{status} (#{duration}ms)"
    end
  end

  def extract_important_headers(request)
    important_headers = {}
    headers_to_log = %w[
      HTTP_ACCEPT
      HTTP_ACCEPT_LANGUAGE
      HTTP_ACCEPT_ENCODING
      HTTP_CONNECTION
      HTTP_CACHE_CONTROL
      HTTP_UPGRADE_INSECURE_REQUESTS
    ]

    headers_to_log.each do |header|
      next unless request.env[header]
      clean_name = header.sub('HTTP_', '').downcase
      important_headers[clean_name] = request.env[header]
    end

    important_headers
  end

  def get_manual_location(ip)
    Rails.logger.info "🔍 Procesando IP: #{ip}"

    case ip
    when /^90\.162\./ # Tu IP de España
      {
        location: { lat: 40.4165, lon: -3.7026 },
        meta: { city: 'Madrid', country: 'Spain', country_code: 'ES' }
      }
    when /^8\.8\./ # Google DNS
      {
        location: { lat: 39.0458, lon: -76.6413 },
        meta: { city: 'Maryland', country: 'United States', country_code: 'US' }
      }
    when /^1\.1\.1\./ # Cloudflare
      {
        location: { lat: 48.8566, lon: 2.3522 },
        meta: { city: 'Paris', country: 'France', country_code: 'FR' }
      }
    else
      {
        location: { lat: 40.4165, lon: -3.7026 },
        meta: { city: 'Madrid', country: 'Spain', country_code: 'ES' }
      }
    end
  end
end
