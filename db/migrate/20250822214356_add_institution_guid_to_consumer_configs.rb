class AddInstitutionGuidToConsumerConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :consumer_configs, :institution_guid, :string
  end
end
