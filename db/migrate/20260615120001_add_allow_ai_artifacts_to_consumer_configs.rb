class AddAllowAiArtifactsToConsumerConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :consumer_configs, :allow_ai_artifacts, :boolean, default: true, null: false
  end
end
