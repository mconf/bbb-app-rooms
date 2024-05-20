class AddMoodleGroupNameToScheduledMeetings < ActiveRecord::Migration[6.1]
  def change
    add_column(:scheduled_meetings, :moodle_group_name, :string)
  end
end
