require_relative "boot"

require "rails/all"
require_relative "../lib/simple_json_formatter"
require_relative "../lib/mconf/env"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BbbAppRooms
  class Application < Rails::Application
    VERSION = "1.1.1"

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.0

    config.eager_load_paths << Rails.root.join('lib')

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    config.url_host = Mconf::Env.fetch('URL_HOST')
    config.hosts << Mconf::Env.fetch('URL_HOST')
    config.relative_url_root = if Mconf::Env.fetch('RELATIVE_URL_ROOT').blank?
                                 '/rooms'
                               else
                                 "/#{Mconf::Env.fetch('RELATIVE_URL_ROOT')}/rooms"
                               end

    config.build_number = Mconf::Env.fetch('BUILD_NUMBER', VERSION)

    # Omniauth configs for Broker
    config.omniauth_path_prefix = if Mconf::Env.fetch('RELATIVE_URL_ROOT').blank?
                                    '/rooms/auth'
                                  else
                                    "/#{Mconf::Env.fetch('RELATIVE_URL_ROOT')}/rooms/auth"
                                  end
    config.omniauth_site = {}
    config.omniauth_site[:bbbltibroker] = Mconf::Env.fetch('OMNIAUTH_BBBLTIBROKER_SITE', 'http://localhost:3000')
    config.omniauth_root = {}
    config.omniauth_root[:bbbltibroker] = ''
    config.omniauth_root[:bbbltibroker] = "/#{Mconf::Env.fetch('OMNIAUTH_BBBLTIBROKER_ROOT')}" if Mconf::Env.fetch('OMNIAUTH_BBBLTIBROKER_ROOT')
    config.omniauth_key = {}
    config.omniauth_key[:bbbltibroker] = Mconf::Env.fetch('OMNIAUTH_BBBLTIBROKER_KEY', '')
    config.omniauth_secret = {}
    config.omniauth_secret[:bbbltibroker] = Mconf::Env.fetch('OMNIAUTH_BBBLTIBROKER_SECRET', '')

    config.assets.prefix = if Mconf::Env.fetch('RELATIVE_URL_ROOT').blank?
                             '/rooms/assets'
                           else
                             "/#{Mconf::Env.fetch('RELATIVE_URL_ROOT')}/rooms/assets"
                           end

    config.default_timezone = Mconf::Env.fetch('DEFAULT_TIMEZONE', 'UTC')
    config.force_default_timezone = Mconf::Env.fetch_boolean('FORCE_DEFAULT_TIMEZONE', false)

    config.app_name = Mconf::Env.fetch('APP_NAME', 'BbbAppRooms')

    # ActiveJob
    config.active_job.queue_adapter = :resque

    ### Log configs
    config.log_level = Mconf::Env.fetch('LOG_LEVEL', :debug)
    # use a json formatter to match lograge's logs
    config.log_formatter = SimpleJsonFormatter.new if Mconf::Env.fetch_boolean('LOGRAGE_ENABLED', false)

    # App_launch configs
    config.launch_duration_mins = Mconf::Env.fetch_int('APP_LAUNCH_DURATION_MINS', 30).minutes
    config.launch_remove_old_on_launch = Mconf::Env.fetch_boolean("APP_LAUNCH_REMOVE_OLD_ON_LAUNCH", true)
    config.launch_days_to_delete = Mconf::Env.fetch_int('APP_LAUNCH_DAYS_TO_DELETE', 15)
    config.launch_limit_for_delete = Mconf::Env.fetch_int('APP_LAUNCH_LIMIT_FOR_DELETE', 1000)

    ### Themes configs
    config.theme = Mconf::Env.fetch('APP_THEME')
    unless config.theme.blank?
      # FIX ME: why we need this now?
      config.eager_load_paths << Rails.root.join('themes', config.theme, 'helpers')

      config.paths['app/helpers']
        .unshift(Rails.root.join('themes', config.theme, 'helpers'))
      config.paths['app/views']
        .unshift(Rails.root.join('themes', config.theme, 'mailers', 'views'))
        .unshift(Rails.root.join('themes', config.theme, 'views'))
      I18n.load_path +=
        Dir[Rails.root.join('themes', config.theme, 'config', 'locales', '*.{rb,yml}')]
      # see config/initializers/assets for more theme configs
    end

    # ActionCable
    config.cable_enabled = Mconf::Env.fetch_boolean('CABLE_ENABLED', false)
    config.cable_polling_secs = Mconf::Env.fetch_int('CABLE_POLLING_SECS', 30)
    config.cable_btn_timeout = Mconf::Env.fetch_int('CABLE_BTN_TIMEOUT', 60000)

    # Browser timezone
    config.browser_time_zone_secure_cookie = !Mconf::Env.fetch_boolean('COOKIES_SECURE_OFF', false)
    config.browser_time_zone_same_site_cookie = Mconf::Env.fetch('COOKIES_SAME_SITE', 'None')
    config.browser_time_zone_default_tz = config.default_timezone

    # Integration with Google Tag Manager
    config.gtm_id = Mconf::Env.fetch('MCONF_GTM_ID', '')
    config.gtm_enabled_keys = Mconf::Env.fetch('MCONF_GTM_ENABLED_KEYS', '')

    # AdOpt configuration
    config.adopt_website_code = Mconf::Env.fetch('MCONF_ADOPT_WEBSITE_CODE', '')

    # Redis configurations. Defaults to a localhost instance.
    config.redis_host      = Mconf::Env.fetch('MCONF_REDIS_HOST')
    config.redis_port      = Mconf::Env.fetch('MCONF_REDIS_PORT')
    config.redis_db        = Mconf::Env.fetch('MCONF_REDIS_DB')
    config.redis_password  = Mconf::Env.fetch('MCONF_REDIS_PASSWORD')

    ### Meetings page configs
    config.meetings_per_page = Mconf::Env.fetch_int('MEETINGS_PER_PAGE', 25)
    # Meeting artifacts
    config.meeting_learning_dashboard_url      = Mconf::Env.fetch('MCONF_LEARNING_DASHBOARD_URL')
    config.meeting_notes_filename              = 'notes.txt'
    config.meeting_participants_filename       = 'activities.txt'
    config.meeting_learning_dashboard_filename = 'learning_dashboard.json'
    # Enable playback URL authentication through getRecordingToken
    config.playback_url_authentication = Mconf::Env.fetch_boolean('PLAYBACK_URL_AUTHENTICATION', false)

    # Eduplay integration
    config.eduplay_enabled            = Mconf::Env.fetch_boolean('EDUPLAY_ENABLED', false)
    config.eduplay_default_tags       = Mconf::Env.fetch('MCONF_EDUPLAY_DEFAULT_TAGS', '').split(',')
    config.omniauth_eduplay_key       = Mconf::Env.fetch('MCONF_OMNIAUTH_EDUPLAY_KEY')
    config.omniauth_eduplay_url       = Mconf::Env.fetch('MCONF_OMNIAUTH_EDUPLAY_URL')
    config.omniauth_eduplay_secret    = Mconf::Env.fetch('MCONF_OMNIAUTH_EDUPLAY_SECRET')
    config.omniauth_eduplay_redirect_callback  = Mconf::Env.fetch('MCONF_OMNIAUTH_EDUPLAY_REDIRECT_CALLBACK')

    # Filesender integration
    config.filesender_enabled           = Mconf::Env.fetch_boolean('FILESENDER_ENABLED', false)
    config.filesender_client_id         = Mconf::Env.fetch('MCONF_FILESENDER_CLIENT_ID')
    config.filesender_redirect_callback = Mconf::Env.fetch('MCONF_FILESENDER_REDIRECT_CALLBACK')
    config.filesender_service_url       = Mconf::Env.fetch('MCONF_FILESENDER_SERVICE_URL')
    config.filesender_client_secret     = Mconf::Env.fetch('MCONF_FILESENDER_CLIENT_SECRET')

    # RNP CHAT
    config.rnp_chat_id = Mconf::Env.fetch('RNP_CHAT_ID', '')

    # Moodle API
    config.moodle_api_timeout = Mconf::Env.fetch_int('MCONF_MOODLE_API_TIMEOUT', 5)
    config.moodle_recurring_events_month_period = Mconf::Env.fetch_int('MCONF_MOODLE_RECURRING_EVENTS_MONTH_PERIOD', 12)

    # Mconf Data API
    config.data_api_url = Mconf::Env.fetch('MCONF_DATA_API_URL', '')
    config.data_reports_enabled = Mconf::Env.fetch_boolean('MCONF_DATA_REPORTS_ENABLED', true)

    ### Bigbluebutton API
    config.bigbluebutton_endpoint = Mconf::Env.fetch('BIGBLUEBUTTON_ENDPOINT',
    'http://test-install.blindsidenetworks.com/bigbluebutton/api')
    config.bigbluebutton_endpoint_internal = Mconf::Env.fetch('BIGBLUEBUTTON_ENDPOINT_INTERNAL')
    config.bigbluebutton_secret = Mconf::Env.fetch('BIGBLUEBUTTON_SECRET','8cd8ef52e8e101574e400365b55e11a6')
    config.bigbluebutton_moderator_roles = Mconf::Env.fetch('BIGBLUEBUTTON_MODERATOR_ROLES',
    'Instructor,Faculty,Teacher,Mentor,Administrator,Admin')
    config.ajax_timeout = Mconf::Env.fetch_int('MCONF_AJAX_TIMEOUT', 15000)
    config.bbb_api_timeout = Mconf::Env.fetch_int('MCONF_BBB_API_TIMEOUT', 15)
    # Pre-open the join_api_url with `redirect=false` to check whether the user can join the meeting
    # before actually redirecting him
    config.check_can_join_meeting = Mconf::Env.fetch_boolean("CHECK_CAN_JOIN_MEETING", true)
    # polling interval, in milliseconds
    config.running_polling_delay = Mconf::Env.fetch_int('RUNNING_POLLING_DELAY', 10000)

  end
end
