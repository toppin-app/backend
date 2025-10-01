# Temporary file to test Elasticsearch logging
Rails.application.config.after_initialize do
  if defined?($elasticsearch_client)
    begin
      # Send a test log entry
      test_log = {
        timestamp: Time.current.iso8601,
        level: 'INFO',
        message: 'Test log entry from Rails application',
        environment: Rails.env,
        application: 'toppin-backend-test',
        hostname: Socket.gethostname
      }
      
      index_name = "toppin-backend-logs-#{Date.current.strftime('%Y.%m.%d')}"
      
      $elasticsearch_client.index(
        index: index_name,
        body: test_log
      )
      
      Rails.logger.info "✅ Test log sent to Elasticsearch index: #{index_name}"
    rescue => e
      Rails.logger.error "❌ Failed to send test log to Elasticsearch: #{e.message}"
    end
  else
    Rails.logger.error "❌ Elasticsearch client not initialized"
  end
end