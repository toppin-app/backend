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

    # ✅ NUEVO: Verificar si el pipeline existe, si no, crearlo
    ensure_geoip_pipeline_exists

    Rails.logger.info "✅ Elasticsearch middleware initialized successfully"
  rescue => e
    Rails.logger.error "❌ Failed to initialize Elasticsearch client: #{e.message}"
    @elasticsearch_client = nil
  end

  def elasticsearch_enabled?
    ENV['ENABLE_ELASTICSEARCH_LOGGING'] == 'true'
  end

  # ✅ NUEVO: Método para verificar/crear el pipeline
  def ensure_geoip_pipeline_exists
    @elasticsearch_client.ingest.get_pipeline(id: 'geoip-pipeline')
    Rails.logger.info "✅ GeoIP pipeline already exists"
  rescue Elasticsearch::Transport::Transport::Errors::NotFound
    create_geoip_pipeline
  rescue => e
    Rails.logger.warn "⚠️ Could not verify GeoIP pipeline: #{e.message}"
  end

  def create_geoip_pipeline
    @elasticsearch_client.ingest.put_pipeline(
      id: 'geoip-pipeline',
      body: {
        description: 'Add geoip info based on IP address',
        processors: [
          {
            geoip: {
              field: 'ip_address',
              target_field: 'geoip',
              ignore_missing: true,
              ignore_failure: true
            }
          }
        ]
      }
    )
    Rails.logger.info "✅ GeoIP pipeline created successfully"
  rescue => e
    Rails.logger.error "❌ Failed to create GeoIP pipeline: #{e.message}"
  end

  def log_request(request, status, duration, timestamp, error = nil)
    return unless @elasticsearch_client

    begin
      log_entry = {
        '@timestamp' => timestamp.iso8601,
        'method' => request.request_method,
        'path' => request.path,
        'full_path' => request.fullpath,
        'query_string' => request.query_string,
        'status_code' => status,
        'duration_ms' => duration,
        'ip_address' => request.ip, # ← El pipeline GeoIP usará esto automáticamente
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

      index_name = "toppin-backend-logs-v2-#{Date.current.strftime('%Y.%m.%d')}"

      # ✅ Usa el pipeline - ahora sí existe
      @elasticsearch_client.index(
        index: index_name,
        pipeline: 'geoip-pipeline',
        body: log_entry
      )

    rescue => e
      Rails.logger.error "Failed to log to Elasticsearch: #{e.message}"
      Rails.logger.error "Error details: #{e.backtrace.first(5).join("\n")}" if Rails.env.development?
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
end
