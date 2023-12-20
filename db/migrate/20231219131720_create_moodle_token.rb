class CreateMoodleToken < ActiveRecord::Migration[6.1]
  def change
    create_table :moodle_tokens do |t|
      t.references :consumer_config, foreign_key: true
      t.string :token
      t.string :url
      t.timestamps
    end
  end
end
