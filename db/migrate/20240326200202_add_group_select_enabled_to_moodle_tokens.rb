class AddGroupSelectEnabledToMoodleTokens < ActiveRecord::Migration[6.1]
  def change
    add_column(:moodle_tokens, :group_select_enabled, :boolean, default: false)
  end
end
