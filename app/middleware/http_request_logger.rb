# HTTP Request Logger Middleware for Elasticsearch
class HttpRequestLogger
  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless $elasticsearch_client

    request = ActionDispatch::Request.new(env)
    start_time = Time.current

    begin
      # Call the next middleware
      status, headers, response = @app.call(env)

      # Calculate duration
      duration = ((Time.current - start_time) * 1000).round(2)

      # Extract response body
      response_body = extract_response_body(response)

      # Log the request
      log_http_request(request, status, duration, response_body)

      [status, headers, response]
    rescue => error
      # Log the error
      duration = ((Time.current - start_time) * 1000).round(2)
      log_http_error(request, error, duration)
      raise error
    end
  end

  private

  def extract_response_body(response)
    return nil unless response.respond_to?(:body)
    
    body_content = if response.body.respond_to?(:each)
      parts = []
      response.body.each { |part| parts << part }
      parts.join
    else
      response.body.to_s
    end

    # Limitar tamaño para no saturar logs
    return nil if body_content.blank?
    body_content.length > 5000 ? "#{body_content[0..5000]}... (truncated)" : body_content
  rescue => e
    Rails.logger.error "Error extracting response body: #{e.message}"
    nil
  end

  def safe_params(request)
    # Extraer parámetros del request
    params = {}
    
    # Parámetros de query string
    params.merge!(request.query_parameters) if request.query_parameters.present?
    
    # Parámetros del body (POST/PUT/PATCH)
    if request.content_type&.include?('json')
      begin
        body = request.body.read
        request.body.rewind # Important: rewind para que Rails pueda leerlo después
        params.merge!(JSON.parse(body)) if body.present?
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse JSON body: #{e.message}"
      end
    elsif request.form_data?
      params.merge!(request.request_parameters)
    end

    # Filtrar parámetros sensibles
    filter_sensitive_params(params)
  rescue => e
    Rails.logger.error "Error extracting params: #{e.message}"
    {}
  end

  def filter_sensitive_params(params)
    sensitive_keys = ['password', 'password_confirmation', 'token', 'secret', 'api_key', 'credit_card']
    
    params.each do |key, value|
      if sensitive_keys.any? { |sensitive| key.to_s.downcase.include?(sensitive) }
        params[key] = '[FILTERED]'
      elsif value.is_a?(Hash)
        filter_sensitive_params(value)
      elsif value.is_a?(Array) && value.first.is_a?(Hash)
        value.each { |item| filter_sensitive_params(item) if item.is_a?(Hash) }
      end
    end
    
    params
  end

  def log_http_request(request, status, duration, response_body = nil)
    begin
      # Extraer parámetros del request
      request_params = safe_params(request)

      log_entry = {
        '@timestamp' => Time.current.iso8601,
        'event_type' => 'http_request',
        'http_method' => request.request_method,
        'path' => request.path,
        'full_url' => request.url,
        'status_code' => status,
        'duration_ms' => duration,
        'client_ip' => request.remote_ip,
        'user_agent' => request.user_agent,
        'referer' => request.referer,
        'host' => request.host,
        'query_string' => request.query_string,
        'content_type' => request.content_type,
        'environment' => Rails.env,
        'application' => 'toppin-backend',
        'server_name' => Socket.gethostname,
        'log_level' => determine_log_level(status)
      }

      # Agregar parámetros del request
      log_entry['request_params'] = request_params if request_params.present?

      # Agregar response body si es JSON
      if response_body.present? && request.content_type&.include?('json')
        begin
          parsed_response = JSON.parse(response_body)
          log_entry['response_body'] = parsed_response
        rescue JSON::ParserError
          log_entry['response_body_text'] = response_body
        end
      end

      # Add request ID if available
      log_entry['request_id'] = request.uuid if request.respond_to?(:uuid)

      # Add authentication info
      if request.headers['Authorization'].present?
        log_entry['has_authorization'] = true
        log_entry['auth_type'] = request.headers['Authorization'].split(' ').first
      end

      # Add request body size
      log_entry['content_length'] = request.content_length if request.content_length

      index_name = "toppin-backend-logs-#{Date.current.strftime('%Y.%m.%d')}"
      
      $elasticsearch_client.index(
        index: index_name,
        body: log_entry
      )

      # Also log to Rails logger for local development
      Rails.logger.info "#{request.request_method} #{request.path} - #{status} (#{duration}ms)"

    rescue => e
      Rails.logger.error "Failed to log HTTP request to Elasticsearch: #{e.message}"
    end
  end

  def log_http_error(request, error, duration)
    begin
      log_entry = {
        '@timestamp' => Time.current.iso8601,
        'event_type' => 'http_error',
        'http_method' => request.request_method,
        'path' => request.path,
        'full_url' => request.url,
        'duration_ms' => duration,
        'error_class' => error.class.name,
        'error_message' => error.message,
        'error_backtrace' => error.backtrace&.first(5),
        'client_ip' => request.remote_ip,
        'user_agent' => request.user_agent,
        'environment' => Rails.env,
        'application' => 'toppin-backend',
        'server_name' => Socket.gethostname,
        'log_level' => 'ERROR'
      }

      index_name = "toppin-backend-logs-#{Date.current.strftime('%Y.%m.%d')}"
      
      $elasticsearch_client.index(
        index: index_name,
        body: log_entry
      )

    rescue => e
      Rails.logger.error "Failed to log HTTP error to Elasticsearch: #{e.message}"
    end
  end

  def determine_log_level(status_code)
    case status_code
    when 200..299
      'INFO'
    when 300..399
      'WARN'
    when 400..499
      'WARN'
    when 500..599
      'ERROR'
    else
      'INFO'
    end
  end
end