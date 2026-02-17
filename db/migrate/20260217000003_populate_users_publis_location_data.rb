class PopulateUsersPublisLocationData < ActiveRecord::Migration[6.0]
  def up
    # Popular los registros existentes con la ubicación actual del usuario
    UserPubli.find_each do |user_publi|
      next if user_publi.locality.present?
      
      user = user_publi.user
      user_publi.update_columns(
        locality: user.location_city,
        country: user.location_country,
        lat: user.lat,
        lng: user.lng
      )
    end
  end

  def down
    # No hacer nada en el rollback
  end
end
