# Resque tasks
require 'resque/tasks'
require 'resque/scheduler/tasks'
require 'logger'

task "resque:setup" => :environment

namespace :resque do
  task :setup do
    require 'resque'
    require 'resque-scheduler'

    # If you want to be able to dynamically change the schedule,
    # uncomment this line.  A dynamic schedule can be updated via the
    # Resque::Scheduler.set_schedule (and remove_schedule) methods.
    # When dynamic is set to true, the scheduler process looks for
    # schedule changes and applies them on the fly.
    # Note: This feature is only available in >=2.0.0.
    # Resque::Scheduler.dynamic = true

    # Scheduler configuration
    yml_schedule     = YAML.load_file("config/jobs_schedule.yml")
    wrapped_schedule = ActiveScheduler::ResqueWrapper.wrap yml_schedule
    Resque.schedule  = wrapped_schedule
  end
end
