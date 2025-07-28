class CreateTmdbUserData < ActiveRecord::Migration[6.0]
  def change
    create_table :tmdb_user_data do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.string :poster_path
      t.text :overview
      t.integer :tmdb_id
      t.string :media_type # "movie" o "tv"
      t.timestamps
    end
  end
end