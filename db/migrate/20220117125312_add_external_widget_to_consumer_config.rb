class AddExternalWidgetToConsumerConfig < ActiveRecord::Migration[6.0]
  def change
    add_column(:consumer_configs, :external_widget, :string, default: "")
  end
end
