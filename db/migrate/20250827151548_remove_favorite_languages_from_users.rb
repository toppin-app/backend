class RemoveFavoriteLanguagesFromUsers < ActiveRecord::Migration[6.0]
  def change
    remove_column :users, :favorite_languages, :text
  end
end