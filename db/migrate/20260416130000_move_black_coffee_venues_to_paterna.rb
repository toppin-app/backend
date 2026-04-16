class MoveBlackCoffeeVenuesToPaterna < ActiveRecord::Migration[6.0]
  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
    self.primary_key = 'id'
  end

  TARGET_CITY = 'Paterna'.freeze
  TARGET_LATITUDE = BigDecimal('39.5037093').freeze
  TARGET_LONGITUDE = BigDecimal('-0.4431618').freeze

  def up
    stats = connection.select_one(<<~SQL.squish) || {}
      SELECT AVG(latitude) AS avg_latitude, AVG(longitude) AS avg_longitude
      FROM venues
      WHERE latitude IS NOT NULL
        AND longitude IS NOT NULL
    SQL

    average_latitude = stats['avg_latitude']
    average_longitude = stats['avg_longitude']

    if average_latitude.blank? || average_longitude.blank?
      say 'No Black Coffee venues with coordinates found, skipping relocation.'
      return
    end

    latitude_offset = TARGET_LATITUDE - BigDecimal(average_latitude.to_s)
    longitude_offset = TARGET_LONGITUDE - BigDecimal(average_longitude.to_s)
    timestamp = Time.current

    say_with_time 'Moving Black Coffee venues to Paterna' do
      VenueRecord.where.not(latitude: nil, longitude: nil).update_all(
        [
          'latitude = latitude + ?, longitude = longitude + ?, city = ?, updated_at = ?',
          latitude_offset.to_f,
          longitude_offset.to_f,
          TARGET_CITY,
          timestamp
        ]
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Black Coffee venue relocation to Paterna cannot be reverted automatically'
  end
end
