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

  # 🌍 Geolocalización REAL usando API de ipapi.co (Gratis: 1000 requests/día)
  def get_location_from_ip(ip)
    # Localhost / IPs privadas - no gastar requests de API
    if ip =~ /^127\./ || ip == '::1' || ip =~ /^192\.168\./ || ip =~ /^10\./ || ip =~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
      return {
        location: { lat: 40.4165, lon: -3.7026 },
        city: 'Local',
        country: 'Local Network',
        country_code: 'XX'
      }
    end

    # Usar cache para no hacer la misma petición varias veces
    cache_key = "geoip:#{ip}"
    cached_data = Rails.cache.read(cache_key)
    return cached_data if cached_data

    begin
      # API gratuita de ipapi.co - 1000 requests/día sin API key
      # Para más requests, registrarse en https://ipapi.co/
      require 'net/http'
      require 'json'
      
      uri = URI("https://ipapi.co/#{ip}/json/")
      response = Net::HTTP.get_response(uri)
      
      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        
        location_data = {
          location: { 
            lat: data['latitude'].to_f, 
            lon: data['longitude'].to_f 
          },
          city: data['city'] || 'Unknown',
          country: data['country_name'] || 'Unknown',
          country_code: data['country_code'] || 'XX',
          region: data['region'] || 'Unknown',
          postal: data['postal'] || 'Unknown',
          timezone: data['timezone'] || 'Unknown'
        }
        
        # Cachear por 24 horas (las IPs no cambian de ubicación frecuentemente)
        Rails.cache.write(cache_key, location_data, expires_in: 24.hours)
        
        Rails.logger.info "✅ Geolocalización obtenida para #{ip}: #{data['city']}, #{data['country_name']}"
        return location_data
      else
        Rails.logger.warn "⚠️ Error en API de geolocalización: #{response.code}"
        return default_location
      end
      
    rescue => e
      Rails.logger.error "❌ Error obteniendo geolocalización: #{e.message}"
      return default_location
    end
  end

  def default_location
    {
      location: { lat: 40.4165, lon: -3.7026 },
      city: 'Unknown',
      country: 'Spain',
      country_code: 'ES'
    }
  end
end
