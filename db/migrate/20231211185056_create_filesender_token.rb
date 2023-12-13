class CreateFilesenderToken < ActiveRecord::Migration[6.1]
  def change
    create_table :filesender_tokens do |t|
      t.string :user_uid
      t.string :token
      t.datetime :expires_at

      t.timestamps
    end
  end
end
