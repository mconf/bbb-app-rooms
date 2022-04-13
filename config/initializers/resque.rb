require 'resque'
require 'resque/server'
require 'resque/scheduler/server'
require 'active_scheduler'

logger = Logger.new(STDOUT)
logger.formatter = Rails.application.config.log_formatter
logger.level = Rails.application.config.log_level
Resque.logger = logger

attrs = {
  host: Rails.application.config.redis_host,
  port: Rails.application.config.redis_port,
  db: Rails.application.config.redis_db
}
attrs[:password] = Rails.application.config.redis_password unless Rails.application.config.redis_password.blank?
Resque.redis = Redis.new(attrs)

# NOTE: the scheduler is configured on lib/tasks/resque.rake

# Authentication for the Resque web interface
Resque::Server.use(Rack::Auth::Basic) do |user, password|
  user == ENV["ADMIN_KEY"]
  password == ENV["ADMIN_PASSWORD"]
end
