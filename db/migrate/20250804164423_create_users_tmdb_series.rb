class CreateUsersTmdbSeries < ActiveRecord::Migration[6.0]
  def change
    create_table :users_tmdb_series do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :poster_path
      t.text :overview
      t.integer :tmdb_id, null: false
      t.string :media_type, default: 'tv'
      t.date :release_date
      t.timestamps
    end
  end
end