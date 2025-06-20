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

    config.autoload_paths += %W(#{config.root}/app/lib)
    config.eager_load_paths += %W(#{config.root}/app/lib)
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
