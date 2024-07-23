class AddShowAllGroupsToMoodleToken < ActiveRecord::Migration[6.1]
  def change
    add_column(:moodle_tokens, :show_all_groups, :boolean, default: true)
  end
end
