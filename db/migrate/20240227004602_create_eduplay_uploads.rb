class CreateEduplayUploads < ActiveRecord::Migration[6.1]
  def change
    create_table :eduplay_uploads do |t|
      t.string :recording_id
      t.string :upload_url

      t.timestamps
    end
  end
end
