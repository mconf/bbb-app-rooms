class AddMarkMoodleAttendanceToScheduledMeetings < ActiveRecord::Migration[6.1]
  def change
    add_column :scheduled_meetings, :mark_moodle_attendance, :boolean
  end
end
