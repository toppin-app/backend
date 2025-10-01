# Elasticsearch configuration for logging
require 'elasticsearch'

# Global Elasticsearch client
if ENV['ELASTICSEARCH_SECURITY_ENABLED'] == 'false'
  # Sin autenticación (solo para desarrollo)
  $elasticsearch_client = Elasticsearch::Client.new(
    url: ENV.fetch('ELASTICSEARCH_URL', 'https://web-elasticsearch-logs.uao3jo.easypanel.host:443'),
    transport_options: {
      request: { timeout: 5 },
      ssl: { verify: false }
    }
  )
else
  # Con autenticación
  $elasticsearch_client = Elasticsearch::Client.new(
    url: ENV.fetch('ELASTICSEARCH_URL', 'https://web-elasticsearch-logs.uao3jo.easypanel.host:443'),
    user: ENV.fetch('ELASTICSEARCH_USER', 'elastic'),
    password: ENV.fetch('ELASTICSEARCH_PASSWORD', 'elasticsearch-logs'),
    transport_options: {
      request: { timeout: 5 },
      ssl: { verify: false } # Para desarrollo - en producción usa certificados válidos
    }
  )
end

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