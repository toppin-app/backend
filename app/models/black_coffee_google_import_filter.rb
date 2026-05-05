class BlackCoffeeGoogleImportFilter < ApplicationRecord
  GENERIC_GOOGLE_TAGS = %w[
    establishment
    food
    point_of_interest
    service
    store
  ].freeze

  validates :category, presence: true, uniqueness: true
  validate :category_must_be_importable

  before_validation :normalize_filter_lists

  def self.importable_categories
    GooglePlacesBlackCoffeeClient.importable_categories
  end

  def self.storage_ready?
    ActiveRecord::Base.connection.data_source_exists?(table_name)
  rescue StandardError
    false
  end

  def self.for_category(category)
    normalized_category = category.to_s
    return new(category: normalized_category) unless storage_ready?

    find_or_initialize_by(category: normalized_category)
  end

  def self.active
    return none unless storage_ready?

    all.select(&:active_filters?).sort_by { |filter| importable_categories.index(filter.category).to_i }
  end

  def self.enhance_config(category, config)
    filter = for_category(category)

    config.merge(
      dynamic_filter: filter,
      effective_aggregate_excluded_primary_types: filter.effective_aggregate_excluded_primary_types(config),
      effective_aggregate_excluded_types: filter.effective_aggregate_excluded_types(config),
      google_total_is_approximate: filter.keyword_filters_active?
    )
  end

  def excluded_primary_types_list
    normalize_list(excluded_primary_types)
  end

  def excluded_types_list
    normalize_list(excluded_types)
  end

  def excluded_keywords_list
    normalize_list(excluded_keywords)
  end

  def active_filters?
    excluded_primary_types_list.any? || excluded_types_list.any? || excluded_keywords_list.any?
  end

  def keyword_filters_active?
    excluded_keywords_list.any?
  end

  def filters_place?(place)
    tags = BlackCoffeeTaxonomy.google_tags_for_place(place)
    primary_type = BlackCoffeeTaxonomy.normalize_google_tag(BlackCoffeeTaxonomy.place_value(place, 'primaryType'))
    searchable_text = normalized_searchable_text(place)

    excluded_primary_types_list.include?(primary_type) ||
      (excluded_types_list & tags).any? ||
      excluded_keywords_list.any? { |keyword| searchable_text.include?(BlackCoffeeTaxonomy.normalized_match_text(keyword)) }
  end

  def effective_aggregate_excluded_primary_types(config = {})
    (Array(config[:aggregate_excluded_primary_types]) + excluded_primary_types_list).uniq
  end

  def effective_aggregate_excluded_types(config = {})
    (Array(config[:aggregate_excluded_types]) + excluded_types_list).uniq
  end

  def invalidate_google_totals!
    return unless ActiveRecord::Base.connection.data_source_exists?('black_coffee_import_region_categories')

    attributes = {
      google_total_count: nil,
      google_total_counted_at: nil,
      google_total_count_error: nil,
      updated_at: Time.current
    }
    if BlackCoffeeImportRegionCategory.column_names.include?('google_total_count_error_details')
      attributes[:google_total_count_error_details] = nil
    end

    BlackCoffeeImportRegionCategory.where(category: category).update_all(attributes)
  end

  private

  def category_must_be_importable
    return if self.class.importable_categories.include?(category.to_s)

    errors.add(:category, 'no es valida para el importador')
  end

  def normalize_filter_lists
    self.excluded_primary_types = normalize_list(excluded_primary_types)
    self.excluded_types = normalize_list(excluded_types)
    self.excluded_keywords = normalize_list(excluded_keywords, preserve_spaces: true)
  end

  def normalize_list(value, preserve_spaces: false)
    Array(value)
      .flat_map { |entry| entry.to_s.split(/[\n,]/) }
      .map { |entry| preserve_spaces ? entry.to_s.strip : BlackCoffeeTaxonomy.normalize_google_tag(entry) }
      .reject(&:blank?)
      .uniq
  end

  def normalized_searchable_text(place)
    BlackCoffeeTaxonomy.normalized_match_text(
      [
        BlackCoffeeTaxonomy.nested_place_value(place, 'displayName', 'text'),
        BlackCoffeeTaxonomy.nested_place_value(place, 'primaryTypeDisplayName', 'text'),
        BlackCoffeeTaxonomy.place_value(place, 'primaryType'),
        BlackCoffeeTaxonomy.place_value(place, 'formattedAddress')
      ].compact.join(' ')
    )
  end
end
