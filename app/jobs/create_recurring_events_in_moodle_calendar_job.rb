require './lib/moodle'

class CreateRecurringEventsInMoodleCalendarJob < ApplicationJob
  queue_as :default

  def perform(moodle_token, scheduled_meeting, context_id, opts={})
    recurring_events = generate_recurring_events(scheduled_meeting)
    
    Resque.logger.info "[JOB] Calling Moodle API create_calendar_event for the #{recurring_events.count} recurring events generated."
    recurring_events.each do |event|
      unless Moodle::API.create_calendar_event(moodle_token, scheduled_meeting.hash_id, event, context_id, opts)
        Resque.logger.error "[CreateRecurringEventsInMoodleCalendarJob] Failed to create Moodle calendar event for meeting '#{scheduled_meeting.name}' (hash_id: #{scheduled_meeting.hash_id}) starting at #{event.start_at}."
      end
      sleep(1)
    end
  end

  private

  def generate_recurring_events(scheduled_meeting)
    start_at = scheduled_meeting.start_at
    recurrence_type = scheduled_meeting.repeat
    defaut_period = Rails.application.config.moodle_recurring_events_month_period
    if recurrence_type == 'weekly'
      event_count = defaut_period*4
      cycle = 1
    else
      event_count = defaut_period*2
      cycle = 2
    end

    Resque.logger.info "[JOB] Generating recurring events"
    recurring_events = []
    event_count.times do |i|
      next_start_at = start_at + (i * cycle).weeks
      recurring_events << ScheduledMeeting.new(
        hash_id: scheduled_meeting.hash_id,
        name: scheduled_meeting.name,
        description: scheduled_meeting.description,
        start_at: next_start_at,
        duration: scheduled_meeting.duration,
      )
    end

    recurring_events
  end
end
