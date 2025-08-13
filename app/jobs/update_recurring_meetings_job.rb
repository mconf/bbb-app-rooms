require './lib/moodle'

class UpdateRecurringMeetingsJob < ApplicationJob
  def perform()
    Room.find_each do |room|
      Resque.logger.info "[JOB] Looking for meetings to be updated in room `#{room.name}`"
      room.scheduled_meetings.inactive.recurring.each do |meeting|
        Resque.logger.info "[JOB] Updating meeting: id=#{meeting.id}, name=#{meeting.name}"
        meeting.update_to_next_recurring_date
        handle_moodle_calendar_events(meeting, room)
      end
    end
    Resque.logger.info "[JOB] All meetings updated."
  end

  def handle_moodle_calendar_events(meeting, room)
    moodle_calendar_events = MoodleCalendarEvent.where(scheduled_meeting_hash_id: meeting.hash_id)
    if moodle_calendar_events.any?
      begin
        app_launch = AppLaunch.find_by(nonce: meeting.created_by_launch_nonce)
        cycle = meeting.weekly? ? 1 : 2
        new_meeting = meeting
        new_meeting.start_at = (moodle_calendar_events.last.start_at + cycle.weeks)
        Resque.logger.info "[UpdateRecurringMeetingsJob] Creating a new event in Moodle Calendar in order to keep meeting's recurrence."
        unless Moodle::API.create_calendar_event(room.moodle_token, meeting.hash_id, new_meeting, app_launch.context_id, {nonce: app_launch.nonce})
          Resque.logger.error "[UpdateRecurringMeetingsJob] Moodle API call to create calendar event failed for meeting `#{meeting.id}`."
        end
      rescue StandardError => e
        Resque.logger.error "Error creating the new calendar event for meeting `#{meeting.id}`, message: #{e.message}."
      end
    end
  end
end
