class CreateFavoriteLanguagesToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :favorite_languages, :string
  end
end