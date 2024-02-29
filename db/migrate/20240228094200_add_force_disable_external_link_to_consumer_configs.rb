class AddForceDisableExternalLinkToConsumerConfigs < ActiveRecord::Migration[6.1]
  def change
    add_column(:consumer_configs, :force_disable_external_link, :boolean, default: false)
  end
end
