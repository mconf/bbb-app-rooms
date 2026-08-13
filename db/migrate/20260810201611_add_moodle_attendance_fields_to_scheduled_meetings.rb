class AddMoodleAttendanceFieldsToScheduledMeetings < ActiveRecord::Migration[8.0]
  def change
    add_column :scheduled_meetings, :moodle_attendance_session_id, :bigint
    add_column :scheduled_meetings, :moodle_attendance_internal_meeting_id, :string
  end
end
