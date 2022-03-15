class AddSharedSecretGuidToConsumerConfigServer < ActiveRecord::Migration[6.1]
  def change
    add_column :consumer_config_servers, :shared_secret_guid, :string, default: ""
  end
end
