class AddAllowLargeMeetingsToConsumerConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :consumer_configs, :allow_large_meetings, :boolean, default: false, null: false
  end
end
