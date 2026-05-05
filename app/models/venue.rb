class Venue < ApplicationRecord
  CATEGORIES = %w[
    restaurante
    hotel
    pub
    cine
    cafeteria
    concierto
    festival
    discoteca
    deportivo
    escape_room
  ].freeze
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
    restaurante: 'restaurante',
    hotel: 'hotel',
    pub: 'pub',
    cine: 'cine',
    cafeteria: 'cafeteria',
    concierto: 'concierto',
    festival: 'festival',
    discoteca: 'discoteca',
    deportivo: 'deportivo',
    escape_room: 'escape_room'
  }

  belongs_to :venue_subcategory, optional: true

  has_many :venue_images, -> { order(:position) }, dependent: :destroy, inverse_of: :venue
  has_many :venue_schedules, dependent: :destroy, inverse_of: :venue
  has_many :user_favorites, dependent: :destroy
  has_many :favorited_by_users, through: :user_favorites, source: :user

  validates :name, :category, :address, :city, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :google_place_id, uniqueness: true, allow_blank: true, if: -> { has_attribute?(:google_place_id) }
  validates :latitude, :longitude, numericality: true

  scope :google_connected, lambda {
    if column_names.include?('google_place_id')
      where.not(google_place_id: [nil, ''])
    else
      none
    end
  }
  before_validation :normalize_tags
  before_validation :normalize_description
  before_validation :normalize_location_metadata
  before_create :assign_identifier

  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :featured_first, -> { order_by_favorites(order(featured: :desc)).order(created_at: :desc) }

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

  def self.filter_by_google_tag(scope, google_tag)
    normalized_tag = BlackCoffeeTaxonomy.normalize_google_tag(google_tag)
    return scope if normalized_tag.blank?

    scope.where("JSON_SEARCH(COALESCE(venues.tags, JSON_ARRAY()), 'one', ?) IS NOT NULL", normalized_tag)
  end

  def self.filter_by_google_primary_type(scope, google_primary_type)
    normalized_type = BlackCoffeeTaxonomy.normalize_google_tag(google_primary_type)
    return scope if normalized_type.blank?

    if column_names.include?('google_primary_type')
      scope.where(
        "(venues.google_primary_type = :value) OR ((venues.google_primary_type IS NULL OR venues.google_primary_type = '') AND JSON_UNQUOTE(JSON_EXTRACT(COALESCE(venues.tags, JSON_ARRAY()), '$[0]')) = :value)",
        value: normalized_type
      )
    else
      scope.where("JSON_UNQUOTE(JSON_EXTRACT(COALESCE(venues.tags, JSON_ARRAY()), '$[0]')) = ?", normalized_type)
    end
  end

  def self.visible_to_app
    column_names.include?('visible') ? where(visible: true) : all
  end

  def self.favorites_count_sql
    <<~SQL.squish
      (
        SELECT COUNT(*)
        FROM user_favorites
        WHERE user_favorites.venue_id = venues.id
      )
    SQL
  end

  def self.order_by_favorites(scope, direction: :desc)
    direction_sql = direction.to_s.downcase == 'asc' ? 'ASC' : 'DESC'
    scope.order(Arel.sql("#{favorites_count_sql} #{direction_sql}"))
  end

  def self.favorite_counts_for(venue_ids)
    ids = Array(venue_ids).compact
    return {} if ids.empty?

    UserFavorite.where(venue_id: ids).group(:venue_id).count
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

  def visible_to_app?
    has_attribute?(:visible) ? visible? : true
  end

  def payment_current_for_dashboard?
    has_attribute?(:payment_current) ? payment_current? : true
  end

  def internal_test_for_dashboard?
    has_attribute?(:internal_test) ? internal_test? : false
  end

  def google_connected?
    has_attribute?(:google_place_id) && google_place_id.present?
  end

  def description_present?
    description.to_s.strip.present?
  end

  def google_primary_type_for_dashboard
    return nil unless google_connected? || Array(tags).any?

    if has_attribute?(:google_primary_type) && google_primary_type.to_s.strip.present?
      google_primary_type.to_s.strip
    else
      Array(tags).map(&:to_s).map(&:strip).reject(&:blank?).first
    end
  end

  def google_primary_type_inferred?
    google_primary_type_for_dashboard.present? && (!has_attribute?(:google_primary_type) || google_primary_type.to_s.strip.blank?)
  end

  def google_secondary_type_list
    stored =
      if has_attribute?(:google_secondary_types)
        Array(google_secondary_types).map(&:to_s).map(&:strip).reject(&:blank?)
      else
        []
      end
    return stored if stored.any?

    primary = google_primary_type_for_dashboard
    Array(tags).map(&:to_s).map(&:strip).reject(&:blank?).uniq.reject { |tag| tag == primary }
  end

  def favorites_count
    return attributes['live_favorites_count'].to_i if attributes.key?('live_favorites_count')

    user_favorites.loaded? ? user_favorites.size : user_favorites.count
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

  def as_black_coffee_json(favorite_venue_ids: [], favorite_counts_by_venue_id: nil, base_url: nil)
    {
      id: id,
      name: name,
      images: image_urls(base_url: base_url),
      category: category,
      subcategory: subcategory_name,
      description: description.presence,
      location: {
        address: address,
        city: city,
        postalCode: has_attribute?(:postal_code) ? postal_code : nil,
        state: has_attribute?(:state) ? state : nil,
        country: has_attribute?(:country) ? country : nil,
        countryCode: has_attribute?(:country_code) ? country_code : nil,
        coordinates: {
          latitude: latitude.to_f,
          longitude: longitude.to_f
        }
      },
      favoritesCount: favorite_count_from(favorite_counts_by_venue_id),
      isFavorite: favorite_venue_ids.include?(id),
      schedule: weekly_schedule,
      featured: featured,
      visible: visible_to_app?,
      googlePlaceId: google_connected? ? google_place_id : nil
    }
  end

  def favorite_count_from(favorite_counts_by_venue_id)
    return favorites_count if favorite_counts_by_venue_id.nil?

    favorite_counts_by_venue_id[id].to_i
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

        attributes = { url: entry[:url], position: next_temporary_position }
        attributes[:source] = entry[:source] if venue_images.klass.column_names.include?('source') && entry.key?(:source)
        if venue_images.klass.column_names.include?('author_attributions') && entry.key?(:author_attributions)
          attributes[:author_attributions] = entry[:author_attributions]
        end

        image = venue_images.create!(attributes)
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

  def sync_google_images!(image_urls:, author_attributions_by_index: [])
    desired_urls = Array(image_urls).map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(10)
    return false if desired_urls.empty?

    current_google_urls = google_managed_images.map { |image| image.url.to_s.strip }.reject(&:blank?)
    current_google_author_attributions = google_managed_images.map { |image| Array(image.author_attributions) }
    desired_author_attributions = desired_urls.each_index.map { |index| Array(author_attributions_by_index[index]) }
    return false if current_google_urls == desired_urls && current_google_author_attributions == desired_author_attributions

    preserved_entries = venue_images.to_a.sort_by(&:position).reject { |image| google_managed_image?(image) }.map do |image|
      { kind: 'existing', id: image.id }
    end
    google_entries = desired_urls.each_with_index.map do |url, index|
      {
        kind: 'remote',
        url: url,
        source: 'google_places',
        author_attributions: desired_author_attributions[index]
      }
    end

    sync_images!(entries: preserved_entries + google_entries, uploaded_files_by_key: {})
    true
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
        unless BlackCoffeeTaxonomy.valid_subcategory?(category, normalized_name)
          errors.add(:venue_subcategory, 'no forma parte del catalogo fijo de Black Coffee')
          raise ActiveRecord::RecordInvalid, self
        end

        VenueSubcategory.find_or_create_by!(name: normalized_name, category: category)
      else
        nil
      end
  end

  private

  def assign_identifier
    self.id ||= "ven_#{SecureRandom.hex(8)}"
  end

  def normalize_description
    self.description = description.to_s.strip.presence
  end

  def normalize_tags
    self.tags = Array(tags).map { |tag| BlackCoffeeTaxonomy.normalize_google_tag(tag) }.reject(&:blank?).uniq
  end

  def normalize_location_metadata
    self.google_place_id = google_place_id.to_s.strip.presence if has_attribute?(:google_place_id)
    self.postal_code = postal_code.to_s.strip.presence if has_attribute?(:postal_code)
    self.state = state.to_s.strip.presence if has_attribute?(:state)
    self.country = country.to_s.strip.presence if has_attribute?(:country)
    self.country_code = country_code.to_s.strip.upcase.presence if has_attribute?(:country_code)
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

  def google_managed_images
    venue_images.to_a.sort_by(&:position).select { |image| google_managed_image?(image) }
  end

  def google_managed_image?(image)
    image.respond_to?(:source) && image.source.to_s == 'google_places'
  end
end
