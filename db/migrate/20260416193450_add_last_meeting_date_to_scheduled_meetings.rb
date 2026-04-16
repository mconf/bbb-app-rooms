class AddLastMeetingDateToScheduledMeetings < ActiveRecord::Migration[8.0]
  def change
    add_column :scheduled_meetings, :last_meeting_date, :datetime
  end
end
