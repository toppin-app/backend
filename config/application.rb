require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsToppin
  class Application < Rails::Application
    config.web_console.permissions = '0.0.0.0/0'
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0
    config.time_zone = "Europe/Madrid"
    
    # Autoload lib directory
    config.autoload_paths << Rails.root.join('lib')
    config.eager_load_paths << Rails.root.join('lib')

    # Load Elasticsearch middleware if enabled
    config.before_initialize do
      if ENV['ENABLE_ELASTICSEARCH_LOGGING'] == 'true'
        # Load the middleware class
        require_relative '../app/middleware/elasticsearch_request_logger'
        # Add to middleware stack
        config.middleware.use ElasticsearchRequestLogger
      end
    end

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
