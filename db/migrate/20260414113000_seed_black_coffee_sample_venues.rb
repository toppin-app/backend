require 'base64'
require 'digest'
require 'json'
require 'stringio'
require 'uri'
require 'zlib'

class SeedBlackCoffeeSampleVenues < ActiveRecord::Migration[6.0]
  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
    self.primary_key = 'id'
  end

  class VenueSubcategoryRecord < ActiveRecord::Base
    self.table_name = 'venue_subcategories'
    self.primary_key = 'id'
  end

  class VenueImageRecord < ActiveRecord::Base
    self.table_name = 'venue_images'
  end

  class VenueScheduleRecord < ActiveRecord::Base
    self.table_name = 'venue_schedules'
  end

  class UserFavoriteRecord < ActiveRecord::Base
    self.table_name = 'user_favorites'
  end

  def up
    reset_model_information!
    now = Time.current

    sample_venues.each do |venue_data|
      subcategory_id = ensure_subcategory!(venue_data, now)
      upsert_venue!(venue_data, subcategory_id, now)
      replace_images!(venue_data.fetch('id'), venue_data.fetch('images'), now)
      replace_schedule!(venue_data.fetch('id'), venue_data.fetch('schedule'), now)
    end
  end

  def down
    reset_model_information!

    VenueScheduleRecord.where(venue_id: seeded_venue_ids).delete_all
    VenueImageRecord.where(venue_id: seeded_venue_ids).delete_all
    UserFavoriteRecord.where(venue_id: seeded_venue_ids).delete_all
    VenueRecord.where(id: seeded_venue_ids).delete_all

    seeded_subcategory_ids.each do |subcategory_id|
      next if VenueRecord.where(venue_subcategory_id: subcategory_id).exists?

      VenueSubcategoryRecord.where(id: subcategory_id).delete_all
    end
  end

  private

  def reset_model_information!
    [
      VenueRecord,
      VenueSubcategoryRecord,
      VenueImageRecord,
      VenueScheduleRecord,
      UserFavoriteRecord
    ].each(&:reset_column_information)
  end

  def ensure_subcategory!(venue_data, now)
    raw_name = venue_data['subcategory']
    return nil if raw_name.nil?

    name = raw_name.to_s.strip.downcase
    return nil if name.empty?

    category = venue_data.fetch('category')
    existing = VenueSubcategoryRecord.find_by(category: category, name: name)
    return existing.id if existing

    record = VenueSubcategoryRecord.new(
      id: subcategory_id_for(category, name),
      category: category,
      name: name,
      created_at: now,
      updated_at: now
    )
    record.save!
    record.id
  end

  def upsert_venue!(venue_data, subcategory_id, now)
    location = venue_data.fetch('location')
    coordinates = location.fetch('coordinates')

    venue = VenueRecord.find_or_initialize_by(id: venue_data.fetch('id'))
    venue.assign_attributes(
      name: venue_data.fetch('name'),
      category: venue_data.fetch('category'),
      venue_subcategory_id: subcategory_id,
      description: venue_data.fetch('description'),
      address: location.fetch('address'),
      city: location.fetch('city'),
      latitude: coordinates.fetch('latitude'),
      longitude: coordinates.fetch('longitude'),
      favorites_count: venue_data.fetch('favoritesCount'),
      featured: venue_data.fetch('featured'),
      tags: venue_data.fetch('tags'),
      updated_at: now
    )
    venue.created_at ||= now
    venue.save!
  end

  def replace_images!(venue_id, image_urls, now)
    normalized_urls = normalize_image_urls(image_urls)

    if normalized_urls.empty?
      raise ActiveRecord::MigrationError, "Venue #{venue_id} does not include valid image URLs"
    end

    VenueImageRecord.where(venue_id: venue_id).delete_all

    normalized_urls.each_with_index do |url, index|
      VenueImageRecord.create!(
        venue_id: venue_id,
        url: url,
        position: index,
        created_at: now,
        updated_at: now
      )
    end
  end

  def replace_schedule!(venue_id, schedule_entries, now)
    VenueScheduleRecord.where(venue_id: venue_id).delete_all

    Array(schedule_entries).each do |entry|
      slots = Array(entry['slots'])
      closed = entry['closed'] || slots.empty?

      if closed
        VenueScheduleRecord.create!(
          venue_id: venue_id,
          day: entry.fetch('day'),
          closed: true,
          slot_index: 0,
          created_at: now,
          updated_at: now
        )
        next
      end

      slots.each_with_index do |slot, index|
        VenueScheduleRecord.create!(
          venue_id: venue_id,
          day: entry.fetch('day'),
          closed: false,
          slot_open: slot.fetch('open'),
          slot_close: slot.fetch('close'),
          slot_index: index,
          created_at: now,
          updated_at: now
        )
      end
    end
  end

  def normalize_image_urls(image_urls)
    Array(image_urls)
      .map { |url| url.to_s.strip }
      .reject(&:empty?)
      .select { |url| valid_image_url?(url) }
      .uniq
  end

  def valid_image_url?(url)
    URI::DEFAULT_PARSER.make_regexp(%w[http https]).match?(url)
  end

  def seeded_venue_ids
    sample_venues.map { |venue| venue.fetch('id') }
  end

  def seeded_subcategory_ids
    sample_venues.filter_map do |venue|
      raw_name = venue['subcategory']
      next if raw_name.nil?

      name = raw_name.to_s.strip.downcase
      next if name.empty?

      subcategory_id_for(venue.fetch('category'), name)
    end.uniq
  end

  def subcategory_id_for(category, name)
    "sub_#{Digest::SHA256.hexdigest("#{category}:#{name}")[0, 12]}"
  end

  def sample_venues
    @sample_venues ||= begin
      json = Zlib::GzipReader.new(StringIO.new(Base64.decode64(sample_venues_payload))).read
      JSON.parse(json)
    end
  end

  def sample_venues_payload
    <<~PAYLOAD.delete("\n")
      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
    PAYLOAD
  end
end
