class RenameAllowDashMrToAllowElosAnalyticsOnConsumerConfigs < ActiveRecord::Migration[8.1]
  def change
    rename_column :consumer_configs, :allow_dash_mr, :allow_elos_analytics
  end
end
