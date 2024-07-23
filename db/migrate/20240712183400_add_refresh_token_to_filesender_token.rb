class AddRefreshTokenToFilesenderToken < ActiveRecord::Migration[6.1]
  def change
    add_column :filesender_tokens, :refresh_token, :text
  end
end
