class AddTrackIdToSpotifyUserData < ActiveRecord::Migration[6.0]
  def change
    add_column :spotify_user_data_controller, :track_id, :string
  end
end