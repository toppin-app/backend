class AddReleaseDateToTmdbUserData < ActiveRecord::Migration[6.0]
  def change
    add_column :tmdb_user_data, :release_date, :date
  end
end