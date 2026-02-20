class PopulateBannerUsersLocationData < ActiveRecord::Migration[6.0]
  def up
    # Popular los registros existentes con la ubicación actual del usuario
    BannerUser.find_each do |banner_user|
      next if banner_user.locality.present?
      
      user = banner_user.user
      banner_user.update_columns(
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
