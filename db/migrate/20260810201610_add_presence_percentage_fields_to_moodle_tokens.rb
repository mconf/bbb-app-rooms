class AddPresencePercentageFieldsToMoodleTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :moodle_tokens, :presence_percentage_enabled, :boolean, default: false, null: false
    add_column :moodle_tokens, :presence_threshold_percentage, :integer, default: 75, null: false
    add_column :moodle_tokens, :partial_presence_threshold_percentage, :integer, default: 10, null: false
  end
end
