class CreateMoodleCalendarEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :moodle_calendar_events do |t|
      t.integer :event_id
      t.string :scheduled_meeting_hash_id

      t.timestamps
    end
  end
end
