class AddAutoStartRecordingToScheduledMeetings < ActiveRecord::Migration[8.0]
  def change
    add_column :scheduled_meetings, :auto_start_recording, :boolean, default: false, null: false
  end
end
