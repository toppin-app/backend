Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false
  config.hosts << "web-backend-ruby.uao3jo.easypanel.host"
  config.hosts << "web-backend-ruby-dev.uao3jo.easypanel.host"
  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true
  config.action_mailer.delivery_method = :mailjet



  config.action_mailer.default_url_options = { host: "toppin-dev.itechglobal.solutions" }

  config.action_mailer.smtp_settings = {
  address:              'in-v3.mailjet.com',
  port:                 587,
  domain:               'innobing.net',
  user_name:            'noreply@innobing.net',
  password:             '1349cb156f45c9a2261b19b9fc2cea35',
  authentication:       :plain,
  enable_starttls_auto: true
}

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

    config.active_storage.service = :local

  # Mount Action Cable outside main process or domain.
  config.action_cable.mount_path = '/cable'
  config.action_cable.url = 'wss://web-backend-ruby.uao3jo.easypanel.host/cable'
  config.action_cable.allowed_request_origins = [ /.+/ ]

  config.action_cable.disable_request_forgery_protection = true

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::FileUpdateChecker
end
