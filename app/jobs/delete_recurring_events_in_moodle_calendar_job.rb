require './lib/moodle'

class DeleteRecurringEventsInMoodleCalendarJob < ApplicationJob
  queue_as :default

  def perform(moodle_token, calendar_events_ids, context_id, opts={})

    calendar_events_ids.each do |event_id|
      Resque.logger.info "[JOB] Calling Moodle API delete_calendar_event for event_id: #{event_id}." 

      Moodle::API.delete_calendar_event(moodle_token, event_id, context_id, opts)
      MoodleCalendarEvent.find_by(event_id: event_id).destroy
      sleep(1)
    end
  end
end
