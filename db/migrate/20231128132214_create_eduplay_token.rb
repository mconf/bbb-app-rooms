class CreateEduplayToken < ActiveRecord::Migration[6.1]
  def change
    create_table :eduplay_tokens do |t|
      t.string :user_uid
      t.string :token
      t.datetime :expires_at

      t.timestamps
    end
  end
end
