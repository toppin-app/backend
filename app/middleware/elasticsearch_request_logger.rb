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
    
    # Ejecutar la aplicación y capturar la respuesta
    status, headers, response = @app.call(env)
    
    end_time = Time.current
    duration = ((end_time - start_time) * 1000).round(2) # en milisegundos
    
    # Log de la petición
    log_request(request, status, duration, start_time)
    
    [status, headers, response]
  rescue => e
    # Si hay error, también lo loggeamos
    end_time = Time.current
    duration = ((end_time - start_time) * 1000).round(2)
    log_request(request, 500, duration, start_time, e.message)
    
    # Re-lanzar el error
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
      # Extraer información de la petición
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

      # Agregar headers importantes
      log_entry['headers'] = extract_important_headers(request)
      
      # Agregar información de autenticación si está disponible
      if request.env['HTTP_AUTHORIZATION']
        log_entry['has_auth'] = true
        log_entry['auth_type'] = request.env['HTTP_AUTHORIZATION'].split(' ').first
      end

      # Si hay error, agregarlo
      if error
        log_entry['error'] = error
        log_entry['level'] = 'ERROR'
      else
        log_entry['level'] = status >= 400 ? 'WARN' : 'INFO'
      end

      # Determinar el índice por fecha
      index_name = "toppin-backend-logs-#{Date.current.strftime('%Y.%m.%d')}"
      
      # Enviar a Elasticsearch
      @elasticsearch_client.index(
        index: index_name,
        body: log_entry
      )

    rescue => e
      # Si falla el logging a Elasticsearch, al menos loggeamos en Rails
      Rails.logger.error "Failed to log to Elasticsearch: #{e.message}"
      Rails.logger.info "#{request.request_method} #{request.fullpath} - #{status} (#{duration}ms)"
    end
  end

  def extract_important_headers(request)
    important_headers = {}
    
    # Headers que nos interesan para el análisis
    headers_to_log = [
      'HTTP_ACCEPT',
      'HTTP_ACCEPT_LANGUAGE',
      'HTTP_ACCEPT_ENCODING',
      'HTTP_CONNECTION',
      'HTTP_CACHE_CONTROL',
      'HTTP_UPGRADE_INSECURE_REQUESTS'
    ]

    headers_to_log.each do |header|
      if request.env[header]
        clean_name = header.sub('HTTP_', '').downcase
        important_headers[clean_name] = request.env[header]
      end
    end

    important_headers
  end
end