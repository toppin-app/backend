require 'digest'

class NormalizeBlackCoffeeHotelSubcategories < ActiveRecord::Migration[6.0]
  HOTEL_CATEGORY = 'hotel'.freeze
  CANONICAL_HOTEL_NAME = 'hotel'.freeze
  LEGACY_HOTEL_NAMES = %w[business boutique escapada].freeze

  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
  end

  class VenueSubcategoryRecord < ActiveRecord::Base
    self.table_name = 'venue_subcategories'
    self.primary_key = 'id'
  end

  def up
    reset_model_information!

    canonical = ensure_canonical_hotel_subcategory!
    legacy_subcategories = VenueSubcategoryRecord.where(
      category: HOTEL_CATEGORY,
      name: LEGACY_HOTEL_NAMES
    )

    legacy_ids = legacy_subcategories.pluck(:id)
    return if legacy_ids.empty?

    VenueRecord.where(venue_subcategory_id: legacy_ids).update_all(
      venue_subcategory_id: canonical.id
    )

    legacy_subcategories.where.not(id: canonical.id).find_each do |subcategory|
      next if VenueRecord.where(venue_subcategory_id: subcategory.id).exists?

      subcategory.destroy!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Hotel subcategories were compacted into a single canonical value'
  end

  private

  def reset_model_information!
    [VenueRecord, VenueSubcategoryRecord].each(&:reset_column_information)
  end

  def ensure_canonical_hotel_subcategory!
    existing = VenueSubcategoryRecord.find_by(
      category: HOTEL_CATEGORY,
      name: CANONICAL_HOTEL_NAME
    )
    return existing if existing

    now = Time.current
    VenueSubcategoryRecord.create!(
      id: canonical_hotel_subcategory_id,
      category: HOTEL_CATEGORY,
      name: CANONICAL_HOTEL_NAME,
      created_at: now,
      updated_at: now
    )
  end

  def canonical_hotel_subcategory_id
    "sub_#{Digest::SHA256.hexdigest("#{HOTEL_CATEGORY}:#{CANONICAL_HOTEL_NAME}")[0, 12]}"
  end
end
