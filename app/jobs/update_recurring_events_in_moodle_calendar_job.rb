require './lib/moodle'

class UpdateRecurringEventsInMoodleCalendarJob < ApplicationJob
  queue_as :default

  def perform(moodle_token, scheduled_meeting, calendar_events_ids, context_id, opts={})
    start_at = scheduled_meeting.start_at
    cycle = scheduled_meeting.weekly? ? 1 : 2

    Resque.logger.info "[JOB] Calling Moodle API update_calendar_event_day for #{calendar_events_ids.count} recurring events."

    calendar_events_ids.each_with_index do |event_id, i|
      next_start_at = start_at + (i * cycle).weeks
      Moodle::API.update_calendar_event_day(moodle_token, event_id, next_start_at, context_id, opts)
      MoodleCalendarEvent.find_by(event_id: event_id).update(start_at: next_start_at)
      sleep(1)
    end
  end
end
