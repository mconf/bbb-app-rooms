class AddMoodleGroupIdToScheduledMeetings < ActiveRecord::Migration[6.1]
  def change
    add_column(:scheduled_meetings, :moodle_group_id, :integer)
  end
end
