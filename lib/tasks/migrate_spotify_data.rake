# lib/tasks/migrate_spotify_data.rake
namespace :migrate do
  desc "Migrar datos de Spotify de users a spotify_user_data"
  task spotify_data: :environment do
    User.find_each do |user|
      (1..6).each do |i|
        image = user.send("spoty#{i}")
        artist_name = user.send("spoty_title#{i}")
        if image.present? && artist_name.present?
          user.spotify_user_data.create(
            image: image,
            artist_name: artist_name
          )
        end
      end
    end
  end
end
