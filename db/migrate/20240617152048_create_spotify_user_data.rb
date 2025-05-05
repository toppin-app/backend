class CreateSpotifyUserData < ActiveRecord::Migration[6.0]
  def change
    create_table :spotify_user_data, options: "DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.bigint :user_id, null: false
      t.string :artist_name
      t.string :image
      t.string :preview_url
      t.string :track_name

      t.timestamps
    end

    add_index :spotify_user_data, :user_id, name: 'index_spotify_user_data_on_user_id'
    add_foreign_key :spotify_user_data, :users, column: :user_id, name: 'fk_spotify_user_data_user_id'
  end
end
