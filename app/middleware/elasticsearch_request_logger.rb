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
      # 🌍 Obtener geolocalización ANTES de crear el log_entry
      location_data = get_location_from_ip(request.ip)

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

      # ✅ Añadir geolocalización manual (mismo formato que GeoIP)
      if location_data
        log_entry['geoip'] = {
          'location' => location_data[:location],
          'city_name' => location_data[:city],
          'country_name' => location_data[:country],
          'country_iso_code' => location_data[:country_code]
        }
      end

      log_entry['headers'] = extract_important_headers(request)

      if request.env['HTTP_AUTHORIZATION']
        log_entry['has_auth'] = true
        log_entry['auth_type'] = request.env['HTTP_AUTHORIZATION'].split(' ').first
      end

      log_entry['level'] = if error
                             'ERROR'
                           elsif status >= 400
                             'WARN'
                           else
                             'INFO'
                           end

      log_entry['error'] = error if error

      index_name = "toppin-backend-logs-v2-#{Date.current.strftime('%Y.%m.%d')}"

      # ❌ NO usar pipeline (no funciona sin GeoIP database)
      @elasticsearch_client.index(
        index: index_name,
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

  # 🌍 Geolocalización manual basada en rangos de IP conocidos
  def get_location_from_ip(ip)
    case ip
    # España - Rangos comunes de ISPs españoles
    when /^83\.48\./, /^90\.162\./, /^88\.27\./, /^80\.34\./, /^84\.88\./
      {
        location: { lat: 40.4165, lon: -3.7026 },
        city: 'Madrid',
        country: 'Spain',
        country_code: 'ES'
      }
    
    # Estados Unidos - Google/Cloudflare DNS
    when /^8\.8\./, /^1\.1\.1\./
      {
        location: { lat: 37.7749, lon: -122.4194 },
        city: 'San Francisco',
        country: 'United States',
        country_code: 'US'
      }
    
    # Reino Unido - Rangos comunes
    when /^86\./, /^87\./
      {
        location: { lat: 51.5074, lon: -0.1278 },
        city: 'London',
        country: 'United Kingdom',
        country_code: 'GB'
      }
    
    # Francia
    when /^90\./, /^91\./
      {
        location: { lat: 48.8566, lon: 2.3522 },
        city: 'Paris',
        country: 'France',
        country_code: 'FR'
      }
    
    # Localhost / IPs privadas
    when /^127\./, /^::1$/, /^192\.168\./, /^10\./, /^172\.(1[6-9]|2[0-9]|3[0-1])\./
      {
        location: { lat: 40.4165, lon: -3.7026 },
        city: 'Local',
        country: 'Local Network',
        country_code: 'XX'
      }
    
    # Default: España (puedes cambiar esto)
    else
      Rails.logger.info "⚠️ Unknown IP range: #{ip}, defaulting to Spain"
      {
        location: { lat: 40.4165, lon: -3.7026 },
        city: 'Unknown',
        country: 'Spain',
        country_code: 'ES'
      }
    end
  end
end
