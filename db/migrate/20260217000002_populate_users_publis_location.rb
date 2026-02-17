class PopulateUsersPublisLocation < ActiveRecord::Migration[6.0]
  def up
    # Popular los registros existentes con la ubicación actual del usuario
    execute <<-SQL
      UPDATE users_publis up
      INNER JOIN users u ON up.user_id = u.id
      SET up.locality = u.location_city,
          up.country = u.location_country,
          up.lat = u.lat,
          up.lng = u.lng
      WHERE up.locality IS NULL
    SQL
  end

  def down
    # No necesitamos hacer nada en el rollback
  end
end
