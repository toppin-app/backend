class Venue < ApplicationRecord
  CATEGORIES = %w[bar restaurante escape_room cine cafeteria].freeze
  DAY_ORDER = %w[L M X J V S D].freeze
  DAY_LABELS = {
    'L' => 'Lunes',
    'M' => 'Martes',
    'X' => 'Miercoles',
    'J' => 'Jueves',
    'V' => 'Viernes',
    'S' => 'Sabado',
    'D' => 'Domingo'
  }.freeze

  enum category: {
    bar: 'bar',
    restaurante: 'restaurante',
    escape_room: 'escape_room',
    cine: 'cine',
    cafeteria: 'cafeteria'
  }

  belongs_to :venue_subcategory, optional: true

  has_many :venue_images, -> { order(:position) }, dependent: :destroy, inverse_of: :venue
  has_many :venue_schedules, dependent: :destroy, inverse_of: :venue
  has_many :user_favorites, dependent: :destroy
  has_many :favorited_by_users, through: :user_favorites, source: :user

  validates :name, :category, :description, :address, :city, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :latitude, :longitude, numericality: true
  validates :favorites_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  before_validation :normalize_tags
  before_create :assign_identifier

  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :featured_first, -> { order(featured: :desc, favorites_count: :desc, created_at: :desc) }

  def self.normalize_text(value)
    value.to_s.strip.downcase.presence
  end

  def self.filter_by_category(scope, category)
    normalized_category = normalize_text(category)
    return scope if normalized_category.blank? || normalized_category == 'all'

    scope.where(category: normalized_category)
  end

  def self.filter_by_subcategory(scope, subcategory)
    normalized_subcategory = normalize_text(subcategory)
    return scope if normalized_subcategory.blank?

    scope.joins(:venue_subcategory)
         .where('LOWER(venue_subcategories.name) = ?', normalized_subcategory)
  end

  def self.distance_sql(lat, lng)
    sanitize_sql_array([
      <<~SQL.squish,
        (
          6371 * ACOS(
            COS(RADIANS(?)) *
            COS(RADIANS(venues.latitude)) *
            COS(RADIANS(venues.longitude) - RADIANS(?)) +
            SIN(RADIANS(?)) *
            SIN(RADIANS(venues.latitude))
          )
        )
      SQL
      lat.to_f,
      lng.to_f,
      lat.to_f
    ])
  end

  def self.with_distance(scope, lat, lng)
    sql = distance_sql(lat, lng)
    scope.with_coordinates.select("venues.*, #{sql} AS distance_km")
  end

  def self.within_distance(scope, lat, lng, max_distance_km)
    sql = distance_sql(lat, lng)
    with_distance(scope, lat, lng).where("#{sql} <= ?", max_distance_km.to_f)
  end

  def self.day_name(day)
    DAY_LABELS[day] || day
  end

  def subcategory_name
    venue_subcategory&.name
  end

  def cover_image_url(base_url: nil)
    image_urls(base_url: base_url).first
  end

  def image_urls(base_url: nil)
    venue_images.to_a.sort_by(&:position).map { |image| image.public_url(base_url: base_url) }.compact
  end

  def weekly_schedule
    grouped = venue_schedules.to_a.group_by(&:day)

    DAY_ORDER.map do |day|
      entries = Array(grouped[day]).sort_by(&:slot_index)
      closed = entries.blank? || entries.all?(&:closed?)

      {
        day: day,
        closed: closed,
        slots: closed ? [] : entries.map { |entry| { open: entry.opening_time, close: entry.closing_time } }
      }
    end
  end

  def as_black_coffee_json(favorite_venue_ids: [], base_url: nil)
    {
      id: id,
      name: name,
      images: image_urls(base_url: base_url),
      category: category,
      subcategory: subcategory_name,
      description: description,
      location: {
        address: address,
        city: city,
        coordinates: {
          latitude: latitude.to_f,
          longitude: longitude.to_f
        }
      },
      favoritesCount: favorites_count,
      isFavorite: favorite_venue_ids.include?(id),
      schedule: weekly_schedule,
      tags: Array(tags),
      featured: featured
    }
  end

  def sync_images!(entries:, uploaded_files_by_key: {})
    normalized_entries = Array(entries)
    current_images = venue_images.to_a.sort_by(&:position)
    current_images_by_id = current_images.index_by(&:id)
    temporary_offset = (current_images.map(&:position).max || -1) + 1000
    seen_existing_ids = {}

    kept_images = normalized_entries.filter_map do |entry|
      next unless entry[:kind] == 'existing'
      next if seen_existing_ids[entry[:id].to_i]

      image_id = entry[:id].to_i
      seen_existing_ids[image_id] = true
      current_images_by_id[image_id]
    end
    removable_images = current_images.reject { |image| kept_images.include?(image) }

    kept_images.each_with_index do |image, index|
      image.update_columns(position: temporary_offset + index)
    end
    removable_images.each(&:destroy!)

    next_temporary_position = temporary_offset + kept_images.size
    reused_existing_ids = {}
    ordered_images = normalized_entries.filter_map do |entry|
      case entry[:kind]
      when 'existing'
        image_id = entry[:id].to_i
        next if reused_existing_ids[image_id]

        reused_existing_ids[image_id] = true
        current_images_by_id[image_id]
      when 'remote'
        next if entry[:url].blank?

        image = venue_images.create!(url: entry[:url], position: next_temporary_position)
        next_temporary_position += 1
        image
      when 'upload'
        file = uploaded_files_by_key[entry[:upload_key].to_s]
        next if file.blank?

        image = venue_images.create!(image: file, position: next_temporary_position)
        next_temporary_position += 1
        image
      end
    end

    ordered_images.each_with_index do |image, index|
      next if image.position == index

      image.update_columns(position: index)
    end
  end

  def sync_schedule!(raw_schedule)
    normalized_schedule = normalize_schedule_payload(raw_schedule)

    venue_schedules.destroy_all
    normalized_schedule.each do |entry|
      if entry[:closed] || entry[:slots].blank?
        venue_schedules.create!(day: entry[:day], closed: true, slot_index: 0)
        next
      end

      entry[:slots].each_with_index do |slot, index|
        venue_schedules.create!(
          day: entry[:day],
          closed: false,
          slot_index: index,
          slot_open: slot[:open],
          slot_close: slot[:close]
        )
      end
    end
  end

  def assign_subcategory_by_name!(subcategory_name)
    normalized_name = self.class.normalize_text(subcategory_name)
    self.venue_subcategory =
      if normalized_name.present?
        VenueSubcategory.find_or_create_by!(name: normalized_name, category: category)
      else
        nil
      end
  end

  private

  def assign_identifier
    self.id ||= "ven_#{SecureRandom.hex(8)}"
  end

  def normalize_tags
    self.tags = Array(tags).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq
  end

  def normalize_schedule_payload(raw_schedule)
    entries =
      case raw_schedule
      when Array
        raw_schedule
      when Hash
        raw_schedule.values
      else
        []
      end

    by_day = entries.each_with_object({}) do |entry, memo|
      next unless entry.respond_to?(:to_h)

      hash = entry.to_h.with_indifferent_access
      day = hash[:day].to_s.upcase
      next unless DAY_ORDER.include?(day)

      closed = ActiveModel::Type::Boolean.new.cast(hash[:closed])
      slots = Array(hash[:slots]).map do |slot|
        slot_hash = slot.respond_to?(:to_h) ? slot.to_h.with_indifferent_access : {}
        open_value = slot_hash[:open].to_s.strip
        close_value = slot_hash[:close].to_s.strip
        next if open_value.blank? || close_value.blank?

        { open: open_value, close: close_value }
      end.compact

      memo[day] = {
        day: day,
        closed: closed || slots.blank?,
        slots: slots
      }
    end

    DAY_ORDER.map do |day|
      by_day[day] || { day: day, closed: true, slots: [] }
    end
  end
end
