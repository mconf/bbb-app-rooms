class ChangeTokenColumnTypeInEduplayTokens < ActiveRecord::Migration[6.1]
  def change
    change_column :eduplay_tokens, :token, :text
  end
end
