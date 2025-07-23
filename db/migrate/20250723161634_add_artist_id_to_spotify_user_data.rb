class AddArtistIdToSpotifyUserData < ActiveRecord::Migration[6.0]
  def change
    add_column :spotify_user_data, :artist_id, :string
  end
end