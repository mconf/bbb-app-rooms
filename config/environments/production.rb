require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  if Mconf::Env.fetch('RAILS_SERVE_STATIC_FILES').present?
    # Disable serving static files from the `/public` folder by default since
    # Apache or NGINX already handles this.
    config.public_file_server.enabled = true

    # Set a cache-control for all assets
    config.public_file_server.headers = {
      "cache-control" => "public, max-age=31536000"
    }
  end

  # Compress JavaScripts and CSS.
  config.assets.js_compressor = :terser
  # config.assets.js_compressor = Uglifier.new(harmony: true)

  # config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = true

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"
  config.asset_host = Mconf::Env.fetch('ASSET_HOST')

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Mount Action Cable outside main process or domain
  config.action_cable.mount_path = Mconf::Env.fetch('CABLE_MOUNT_PATH')
  # config.action_cable.url = 'wss://example.com/cable'
  config.action_cable.allowed_request_origins = ["https://#{config.url_host}"]
  # config.action_cable.allowed_request_origins = [ 'http://example.com', /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = Mconf::Env.fetch_boolean('ENABLE_SSL', true)

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = Mconf::Env.fetch('RAILS_LOG_LEVEL', 'info')

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "bbb_app_rooms_production"

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  # config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = [I18n.default_locale]

  # Don't log any deprecations.
  config.active_support.report_deprecations = :notify

  unless Mconf::Env.fetch_boolean('LOGRAGE_ENABLED', true)
    # Use default logging formatter so that PID and timestamp are not suppressed.
    config.log_formatter = ::Logger::Formatter.new
  end

  # Use a different logger for distributed setups.
  # require "syslog/logger"
  # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new "app-name")

  if Mconf::Env.fetch_boolean('RAILS_LOG_TO_STDOUT', true)
    # Disable output buffering when STDOUT isn't a tty (e.g. Docker images, systemd services)
    STDOUT.sync = true
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = logger
  end

  # configure redis for ActionCable
  config.cache_store = if Mconf::Env.fetch('REDIS_URL').present?
                        # Set up Redis cache store
                        [:redis_cache_store,
                          {
                            url: Mconf::Env.fetch('REDIS_URL'),
                            expires_in: 1.day,
                            connect_timeout: 30, # Defaults to 20 seconds
                            read_timeout: 0.2, # Defaults to 1 second
                            write_timeout: 0.2, # Defaults to 1 second
                            reconnect_attempts: 1, # Defaults to 0
                            error_handler: lambda { |method:, returning:, exception:|
                                              config.logger.warn("Support: Redis cache action #{method} failed and returned '#{returning}': #{exception}")
                                            }
                          }
                        ]
                       else
                          :memory_store
                       end

  config.hosts = Mconf::Env.fetch('WHITELIST_HOST')

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
