# Load Elasticsearch Request Logger middleware after application initialization
Rails.application.config.after_initialize do
  if ENV['ENABLE_ELASTICSEARCH_LOGGING'] == 'true'
    # Ensure the middleware class is loaded
    require Rails.root.join('app', 'middleware', 'elasticsearch_request_logger')
    
    # Add to middleware stack
    Rails.application.config.middleware.use ElasticsearchRequestLogger
    
    Rails.logger.info "✅ Elasticsearch Request Logger middleware loaded"
  else
    Rails.logger.info "ℹ️ Elasticsearch logging disabled"
  end
end