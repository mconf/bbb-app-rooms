class CreateLaunchSigningKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :launch_signing_keys do |t|
      t.string :kid, null: false
      t.text :private_key, null: false
      t.text :public_key, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :launch_signing_keys, :kid, unique: true
    add_index :launch_signing_keys, :active
  end
end
