class AddHideRecordingsHistoryToConsumerConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :consumer_configs, :hide_recordings_history, :boolean, default: false, null: false
  end
end
