class BlackCoffeeImportCandidate < ApplicationRecord
  STATUSES = %w[pending approved rejected duplicate].freeze

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

  before_validation :normalize_arrays

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

  def google_photo_reference_list
    Array(google_photo_references)
  end

  def approve!
    raise ActiveRecord::RecordInvalid, self unless valid_for_approval?
    return approved_venue if approved? && approved_venue.present?

    existing_duplicate = duplicate_venue.presence || find_existing_venue
    if existing_duplicate.present?
      mark_as_duplicate!(existing_duplicate)
      return existing_duplicate
    end

    venue = nil
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
      venue.assign_subcategory_by_name!(subcategory) if subcategory.present?
      venue.save!

      image_url_list.first(10).each_with_index do |url, index|
        image = venue.venue_images.build(url: url, position: index)
        image.source = 'google_places' if image.has_attribute?(:source)
        if image.has_attribute?(:author_attributions)
          image.author_attributions = author_attributions_for_image(index)
        end
        image.save!
      end

      update!(
        status: 'approved',
        approved_venue: venue,
        duplicate_venue: nil,
        reviewed_at: Time.current
      )
      black_coffee_import_run.refresh_counts!
    end

    venue
  end

  def reject!
    update!(status: 'rejected', reviewed_at: Time.current)
    black_coffee_import_run.refresh_counts!
  end

  def mark_as_duplicate!(venue)
    update!(status: 'duplicate', duplicate_venue: venue, reviewed_at: Time.current)
    black_coffee_import_run.refresh_counts!
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
    [
      category,
      subcategory,
      rating.present? ? "google_rating_#{rating}" : nil
    ].compact
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
end
