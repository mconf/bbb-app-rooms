class AddMarkBrightspaceAttendanceToScheduledMeetings < ActiveRecord::Migration[8.0]
  def change
    add_column :scheduled_meetings, :mark_brightspace_attendance, :boolean
  end
end
