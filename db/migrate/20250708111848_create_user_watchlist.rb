class CreateUserWatchlists < ActiveRecord::Migration[6.0]
  def change
    create_table :user_watchlists do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :media_id, null: false # ID en TMDB
      t.string :media_type, null: false # 'movie' o 'tv'

      t.timestamps
    end
    add_index :user_watchlists, [:user_id, :media_id, :media_type], unique: true
  end
end