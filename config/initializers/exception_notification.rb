require 'exception_notification/rails'
require 'resque/failure/multiple'
require 'resque/failure/redis'
require 'exception_notification/resque'

Resque::Failure::Multiple.classes = [Resque::Failure::Redis, ExceptionNotification::Resque]
Resque::Failure.backend = Resque::Failure::Multiple

notifications_enabled = Mconf::Env.fetch_boolean('EXCEPTION_NOTIFICATIONS_ENABLED', false)

if notifications_enabled
  recipients = Mconf::Env.fetch('EXCEPTION_NOTIFICATIONS_RECIPIENTS', '').split(/[\s,;]+/).reject(&:empty?)

  if recipients.any?
    email_prefix = Mconf::Env.fetch('EXCEPTION_NOTIFICATIONS_PREFIX', '[ERROR]')
    sender       = Mconf::Env.fetch('EXCEPTION_NOTIFICATIONS_SENDER', 'no-reply@example.com')

    ExceptionNotification.configure do |config|
      config.add_notifier :email, {
        email_prefix: "#{email_prefix} ",
        sender_address: sender,
        exception_recipients: recipients
      }
    end
  end
end
