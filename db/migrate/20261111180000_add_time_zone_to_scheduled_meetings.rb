class AddTimeZoneToScheduledMeetings < ActiveRecord::Migration[8.0]
  def change
    add_column :scheduled_meetings, :time_zone, :string
  end
end
