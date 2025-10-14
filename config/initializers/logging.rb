require 'logger'
require 'elasticsearch'

# Custom logger that sends logs to Elasticsearch
class ElasticsearchLogger < Logger
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
        message: message.to_s,
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
      STDOUT.puts "Failed to log to Elasticsearch: #{e.message}"
      STDOUT.puts "Original log: #{severity_label(severity)} - #{message}"
    end
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
    payload = {
      host: controller.request.host,
      user_agent: controller.request.user_agent,
      ip: controller.request.remote_ip,
      referer: controller.request.referer
    }
    
    # Add user info if available
    if controller.respond_to?(:current_user) && controller.current_user
      payload[:user_id] = controller.current_user.id
    end
    
    payload
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