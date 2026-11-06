class AddLargeMeetingToScheduledMeetings < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_meetings, :large_meeting, :boolean, default: false, null: false
  end
end
