require 'logger'
require 'elasticsearch'

# Custom logger that sends logs to Elasticsearch
class ElasticsearchLogger < Logger
  JWT_PATTERN = /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/.freeze
  BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9._~+\/-]+=*/i.freeze
  SENSITIVE_VALUE_PATTERN = /(authorization|bearer|token|secret|password|api[_-]?key|client[_-]?secret)(\s*[=:]\s*|\s+)[^\s,;\]\}]+/i.freeze

  def initialize
    super(STDOUT)
    @elasticsearch_client = $elasticsearch_client
  end

  def add(severity, message = nil, progname = nil)
    # Call the original logger first
    super

    # Send to Elasticsearch
    send_to_elasticsearch(severity, message, progname) if @elasticsearch_client
  end

  private

  def send_to_elasticsearch(severity, message, progname)
    begin
      log_entry = {
        timestamp: Time.current.iso8601,
        level: severity_label(severity),
        message: sanitized_message(message),
        progname: progname,
        environment: Rails.env,
        application: 'toppin-backend',
        hostname: Socket.gethostname,
        pid: Process.pid,
        thread_id: Thread.current.object_id
      }

      # Add request context if available
      if defined?(Current) && Current.respond_to?(:request_id)
        log_entry[:request_id] = Current.request_id
      end

      index_name = "toppin-backend-logs-#{Date.current.strftime('%Y.%m.%d')}"
      
      @elasticsearch_client.index(
        index: index_name,
        body: log_entry
      )
    rescue => e
      # Fallback to STDOUT if Elasticsearch fails
      STDOUT.puts "Failed to log to Elasticsearch: #{e.class.name}"
    end
  end

  def sanitized_message(message)
    message
      .to_s
      .gsub(JWT_PATTERN, '[FILTERED]')
      .gsub(BEARER_PATTERN, 'Bearer [FILTERED]')
      .gsub(SENSITIVE_VALUE_PATTERN, '\\1\\2[FILTERED]')
  end

  def severity_label(severity)
    case severity
    when 0 then 'DEBUG'
    when 1 then 'INFO'
    when 2 then 'WARN'
    when 3 then 'ERROR'
    when 4 then 'FATAL'
    else 'UNKNOWN'
    end
  end
end

# Configure Lograge for structured logging (complementary to middleware)
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  
  # Disable default Rails request logging to avoid duplication
  config.lograge.keep_original_rails_log = false
  
  config.lograge.custom_payload do |controller|
    {
      host: controller.request.host,
      request_id: controller.request.request_id
    }
  end

  config.lograge.custom_options = lambda do |event|
    {
      '@timestamp' => Time.current.iso8601,
      environment: Rails.env,
      application: 'toppin-backend',
      event_type: 'rails_controller'
    }
  end
end
