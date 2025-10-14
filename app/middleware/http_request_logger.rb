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

      # Log the request
      log_http_request(request, status, duration)

      [status, headers, response]
    rescue => error
      # Log the error
      duration = ((Time.current - start_time) * 1000).round(2)
      log_http_error(request, error, duration)
      raise error
    end
  end

  private

  def log_http_request(request, status, duration)
    begin
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