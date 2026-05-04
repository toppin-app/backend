class BlackCoffeeImportCandidate < ApplicationRecord
  STATUSES = %w[pending approved rejected duplicate].freeze
  GOOGLE_DAY_TO_BLACK_COFFEE_DAY = {
    0 => 'D',
    1 => 'L',
    2 => 'M',
    3 => 'X',
    4 => 'J',
    5 => 'V',
    6 => 'S'
  }.freeze

  belongs_to :black_coffee_import_run,
             inverse_of: :import_candidates
  belongs_to :black_coffee_import_region,
             inverse_of: :import_candidates
  belongs_to :black_coffee_import_region_category,
             optional: true,
             inverse_of: :import_candidates
  belongs_to :approved_venue,
             class_name: 'Venue',
             optional: true
  belongs_to :duplicate_venue,
             class_name: 'Venue',
             optional: true

  validates :name, :category, :status, presence: true
  validates :category, inclusion: { in: Venue::CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :latitude, :longitude, numericality: true, allow_nil: true

  scope :missing_images, -> {
    where('image_urls IS NULL OR JSON_LENGTH(image_urls) = 0')
  }
  scope :image_refreshable, -> {
    where("(google_photo_references IS NOT NULL AND JSON_LENGTH(google_photo_references) > 0) OR (google_place_id IS NOT NULL AND google_place_id <> '')")
  }

  before_validation :normalize_arrays
  before_validation :truncate_string_columns_to_limits

  def pending?
    status == 'pending'
  end

  def approved?
    status == 'approved'
  end

  def rejected?
    status == 'rejected'
  end

  def duplicate?
    status == 'duplicate'
  end

  def image_url_list
    Array(image_urls).map(&:to_s).reject(&:blank?)
  end

  def missing_images?
    image_url_list.empty?
  end

  def google_photo_reference_list
    Array(google_photo_references)
  end

  def image_refreshable?
    google_photo_reference_list.any? || google_place_id.present?
  end

  def google_opening_hours_descriptions
    Array(google_opening_hours&.dig('weekdayDescriptions')).map(&:to_s).reject(&:blank?)
  end

  def google_schedule_payload
    opening_hours = google_opening_hours
    return if opening_hours.blank?

    periods = Array(opening_hours['periods'])
    return full_week_google_schedule if always_open_periods?(periods)
    return closed_week_google_schedule if opening_hours.key?('periods') && periods.empty?

    slots_by_day = periods.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |period, memo|
      period_hash = google_point(period)
      open_point = google_point(period_hash[:open])
      close_point = google_point(period_hash[:close])
      day = GOOGLE_DAY_TO_BLACK_COFFEE_DAY[open_point['day'].to_i]
      open_time = google_point_time(open_point)
      close_time = google_point_time(close_point)
      next if day.blank? || open_time.blank? || close_time.blank?

      memo[day] << { open: open_time, close: close_time }
    end

    return if slots_by_day.empty?

    Venue::DAY_ORDER.map do |day|
      slots = Array(slots_by_day[day]).uniq.sort_by { |slot| slot[:open] }
      { day: day, closed: slots.blank?, slots: slots }
    end
  end

  def google_type_tags
    BlackCoffeeTaxonomy.google_tags_for_place(raw_payload || {})
  end

  def approve!(refresh_counts: true, preloaded_duplicate: nil)
    raise ActiveRecord::RecordInvalid, self unless valid_for_approval?
    return approved_venue if approved? && approved_venue.present?

    existing_duplicate = preloaded_duplicate.presence || duplicate_venue.presence || find_existing_venue
    if existing_duplicate.present?
      mark_as_duplicate!(existing_duplicate, refresh_counts: refresh_counts)
      return existing_duplicate
    end

    venue = nil
    schedule_payload = google_schedule_payload
    ActiveRecord::Base.transaction do
      venue = Venue.new(
        name: name,
        category: category,
        description: default_description,
        address: address.presence || 'Direccion pendiente de revisar',
        city: city.presence || black_coffee_import_region.name,
        latitude: latitude,
        longitude: longitude,
        featured: false,
        tags: default_tags
      )
      venue.internal_test = false if venue.has_attribute?(:internal_test)
      venue.payment_current = true if venue.has_attribute?(:payment_current)
      venue.visible = true if venue.has_attribute?(:visible)
      venue.google_place_id = google_place_id if venue.has_attribute?(:google_place_id)
      venue.postal_code = postal_code if venue.has_attribute?(:postal_code)
      venue.state = state if venue.has_attribute?(:state)
      venue.country = country if venue.has_attribute?(:country)
      venue.country_code = country_code if venue.has_attribute?(:country_code)
      if subcategory.present? && BlackCoffeeTaxonomy.valid_subcategory?(category, subcategory)
        venue.assign_subcategory_by_name!(subcategory)
      end
      venue.save!

      image_url_list.first(10).each_with_index do |url, index|
        image = venue.venue_images.build(url: url, position: index)
        image.source = 'google_places' if image.has_attribute?(:source)
        if image.has_attribute?(:author_attributions)
          image.author_attributions = author_attributions_for_image(index)
        end
        image.save!
      end
      venue.sync_schedule!(schedule_payload) if schedule_payload.present?

      update!(
        status: 'approved',
        approved_venue: venue,
        duplicate_venue: nil,
        reviewed_at: Time.current
      )
      black_coffee_import_run.refresh_counts! if refresh_counts
    end

    venue
  end

  def reject!(refresh_counts: true)
    update!(status: 'rejected', reviewed_at: Time.current)
    black_coffee_import_run.refresh_counts! if refresh_counts
  end

  def mark_as_duplicate!(venue, refresh_counts: true)
    update!(status: 'duplicate', duplicate_venue: venue, reviewed_at: Time.current)
    black_coffee_import_run.refresh_counts! if refresh_counts
  end

  private

  def valid_for_approval?
    errors.clear
    valid?
    errors.add(:latitude, 'debe estar presente') if latitude.blank?
    errors.add(:longitude, 'debe estar presente') if longitude.blank?
    errors.add(:category, 'no es valida') unless Venue::CATEGORIES.include?(category)

    errors.blank?
  end

  def default_description
    'Local importado desde Google Maps para Black Coffee. Revisa y completa la descripcion antes de destacarlo.'
  end

  def default_tags
    google_type_tags.presence || BlackCoffeeTaxonomy.fallback_internal_tags(category, subcategory)
  end

  def find_existing_venue
    if google_place_id.present? && Venue.column_names.include?('google_place_id')
      venue = Venue.find_by(google_place_id: google_place_id)
      return venue if venue.present?
    end

    normalized_name = name.to_s.strip.downcase
    normalized_city = city.to_s.strip.downcase
    return if normalized_name.blank?

    scope = Venue.where('LOWER(name) = ?', normalized_name)
    scope = scope.where('LOWER(city) = ?', normalized_city) if normalized_city.present?
    scope.first
  end

  def author_attributions_for_image(index)
    reference = google_photo_reference_list[index]
    return [] unless reference.respond_to?(:[])

    reference['author_attributions'] || reference[:author_attributions] || []
  end

  def normalize_arrays
    self.image_urls = Array(image_urls).reject(&:blank?)
    self.google_photo_references = Array(google_photo_references)
    self.author_attributions = Array(author_attributions)
  end

  def truncate_string_columns_to_limits
    self.class.columns.each do |column|
      next unless column.type == :string
      next if column.limit.blank?

      current_value = self[column.name]
      next unless current_value.is_a?(String)
      next if current_value.length <= column.limit

      self[column.name] = current_value.first(column.limit)
    end
  end

  def google_opening_hours
    payload =
      if raw_payload.respond_to?(:with_indifferent_access)
        raw_payload.with_indifferent_access
      else
        {}
      end
    hours = payload[:regularOpeningHours].presence || payload[:currentOpeningHours].presence
    hours.respond_to?(:with_indifferent_access) ? hours.with_indifferent_access : nil
  end

  def google_point(value)
    value.respond_to?(:with_indifferent_access) ? value.with_indifferent_access : {}
  end

  def google_point_time(point)
    return unless point.key?(:hour)

    format('%<hour>02d:%<minute>02d', hour: point[:hour].to_i, minute: point[:minute].to_i)
  end

  def always_open_periods?(periods)
    periods.any? do |period|
      period_hash = google_point(period)
      period_hash[:open].present? && period_hash[:close].blank?
    end
  end

  def full_week_google_schedule
    Venue::DAY_ORDER.map do |day|
      { day: day, closed: false, slots: [{ open: '00:00', close: '23:59' }] }
    end
  end

  def closed_week_google_schedule
    Venue::DAY_ORDER.map { |day| { day: day, closed: true, slots: [] } }
  end
end
