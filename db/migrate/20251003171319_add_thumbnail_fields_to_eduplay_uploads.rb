class AddThumbnailFieldsToEduplayUploads < ActiveRecord::Migration[8.0]
  def change
    add_column :eduplay_uploads, :thumbnail_data, :binary
    add_column :eduplay_uploads, :thumbnail_content_type, :string
  end
end
