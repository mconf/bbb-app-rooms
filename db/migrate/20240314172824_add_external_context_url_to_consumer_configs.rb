class AddExternalContextUrlToConsumerConfigs < ActiveRecord::Migration[6.1]
  def change
    add_column(:consumer_configs, :external_context_url, :string)
  end
end
