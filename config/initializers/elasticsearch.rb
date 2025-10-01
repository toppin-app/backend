# Elasticsearch configuration for logging
require 'elasticsearch'

# Configuration for Elasticsearch client
$elasticsearch_client = Elasticsearch::Client.new(
  hosts: [
    {
      host: ENV.fetch('ELASTICSEARCH_HOST', 'web_elasticsearch-logs'),
      port: ENV.fetch('ELASTICSEARCH_PORT', 9200),
      scheme: ENV.fetch('ELASTICSEARCH_SCHEME', 'http')
    }
  ],
  user: ENV.fetch('ELASTICSEARCH_USER', 'elastic'),
  password: ENV.fetch('ELASTICSEARCH_PASSWORD', 'elasticsearch-logs'),
  transport_options: {
    request: { timeout: 5 }
  }
)

# Test connection on startup (only in non-test environments)
unless Rails.env.test?
  begin
    Rails.logger.info "Testing Elasticsearch connection..."
    response = $elasticsearch_client.ping
    if response
      Rails.logger.info "✅ Elasticsearch connection successful!"
    else
      Rails.logger.warn "❌ Elasticsearch connection failed!"
    end
  rescue => e
    Rails.logger.warn "❌ Elasticsearch connection error: #{e.message}"
  end
end