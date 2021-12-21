require 'resque'
require 'resque/server'
require 'resque/scheduler/server'
require 'active_scheduler'

  logger = Logger.new(STDOUT)
  logger.formatter = proc do |severity, datetime, progname, msg|
    formatted_datetime = datetime.strftime("%Y-%m-%d %H:%M:%S.") << datetime.usec.to_s[0..2].rjust(3)
    "#{formatted_datetime} [#{severity}] #{msg} (pid:#{$$})\n"
  end
  Resque.logger = logger
  Resque.logger.level = Logger::INFO

  attrs = {
    host: Rails.application.config.redis_host,
    port: Rails.application.config.redis_port,
    db: Rails.application.config.redis_db
  }
  attrs[:password] = Rails.application.config.redis_password unless Rails.application.config.redis_password.blank?
  Resque.redis = Redis.new(attrs)

  # Scheduler configuration
  yml_schedule     = YAML.load_file("config/jobs_schedule.yml")
  wrapped_schedule = ActiveScheduler::ResqueWrapper.wrap yml_schedule
  Resque.schedule  = wrapped_schedule
  
  # Authentication for the Resque web interface
  Resque::Server.use(Rack::Auth::Basic) do |user, password|
    user == ENV["ADMIN_KEY"]
    password == ENV["ADMIN_PASSWORD"]
  end
