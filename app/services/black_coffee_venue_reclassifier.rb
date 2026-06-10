require 'json'

class BlackCoffeeVenueReclassifier
  CONFIRMATION_TEXT = 'RECLASIFICAR'.freeze
  SELECTION_SELECTED = 'selected'.freeze
  SELECTION_FILTERED = 'filtered'.freeze
  SELECTION_OPTIONS = {
    SELECTION_SELECTED => 'Solo locales seleccionados',
    SELECTION_FILTERED => 'Todos los resultados filtrados'
  }.freeze

  ACCENT_REPLACEMENTS = {
    'á' => 'a',
    'à' => 'a',
    'ä' => 'a',
    'â' => 'a',
    'ã' => 'a',
    'é' => 'e',
    'è' => 'e',
    'ë' => 'e',
    'ê' => 'e',
    'í' => 'i',
    'ì' => 'i',
    'ï' => 'i',
    'î' => 'i',
    'ó' => 'o',
    'ò' => 'o',
    'ö' => 'o',
    'ô' => 'o',
    'õ' => 'o',
    'ú' => 'u',
    'ù' => 'u',
    'ü' => 'u',
    'û' => 'u',
    'ñ' => 'n',
    'ç' => 'c'
  }.freeze

  attr_reader :name_query,
              :excluded_name_query,
              :categories,
              :city,
              :state,
              :country,
              :google_primary_type,
              :google_tag

  def initialize(params = {})
    normalized_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    normalized_params = normalized_params.with_indifferent_access

    @name_query = normalized_free_text(normalized_params[:name_query] || normalized_params[:q])
    @excluded_name_query = normalized_free_text(normalized_params[:excluded_name_query])
    @categories = normalized_categories(normalized_params[:categories] || normalized_params[:category])
    @city = normalized_free_text(normalized_params[:city])
    @state = normalized_free_text(normalized_params[:state])
    @country = normalized_free_text(normalized_params[:country])
    @google_primary_type = BlackCoffeeTaxonomy.normalize_google_tag(normalized_params[:google_primary_type])
    @google_tag = BlackCoffeeTaxonomy.normalize_google_tag(normalized_params[:google_tag])
  end

  def filters
    {
      name_query: name_query,
      excluded_name_query: excluded_name_query,
      categories: categories,
      city: city,
      state: state,
      country: country,
      google_primary_type: google_primary_type,
      google_tag: google_tag
    }
  end

  def filters_present?
    name_query.present? ||
      excluded_name_query.present? ||
      categories.any? ||
      city.present? ||
      state.present? ||
      country.present? ||
      google_primary_type.present? ||
      google_tag.present?
  end

  def scope
    relation = Venue.all
    relation = apply_name_filter(relation)
    relation = apply_excluded_name_filter(relation)
    relation = relation.where(category: categories) if categories.any?
    relation = apply_location_filter(relation, :city, city)
    relation = apply_location_filter(relation, :state, state)
    relation = apply_location_filter(relation, :country, country)
    relation = Venue.filter_by_google_primary_type(relation, google_primary_type)
    Venue.filter_by_google_tag(relation, google_tag)
  end

  def preview
    relation = scope

    {
      filters: filters,
      venue_count: relation.count,
      category_counts: relation.group(:category).count.sort.to_h,
      city_counts: group_count_if_available(relation, :city).first(8).to_h,
      google_linked_count: google_linked_count(relation),
      google_primary_type_counts: group_count_if_available(relation, :google_primary_type).first(8).to_h
    }
  end

  def reclassify!(target_category:, selection_mode:, selected_ids:, confirmation_text:, changed_by: nil, logger: Rails.logger)
    target = normalized_category(target_category)
    raise ArgumentError, 'Debes elegir una categoria destino valida.' if target.blank?
    raise ArgumentError, "Escribe #{CONFIRMATION_TEXT} para confirmar esta reclasificacion masiva." unless confirmation_text.to_s == CONFIRMATION_TEXT

    venue_ids = venue_ids_for_selection(selection_mode, selected_ids)
    raise ArgumentError, 'Selecciona al menos un local para reclasificar.' if venue_ids.empty?

    now = Time.current
    previous_categories = Venue.where(id: venue_ids).pluck(:id, :category).to_h
    changed_ids = previous_categories.select { |_id, category| category.to_s != target }.keys

    ActiveRecord::Base.transaction do
      if changed_ids.any?
        attributes = {
          category: target,
          updated_at: now
        }
        attributes[:venue_subcategory_id] = nil if has_venue_column?(:venue_subcategory_id)
        attributes[:reviewed_at] = now if has_venue_column?(:reviewed_at)
        attributes[:reviewed_by_id] = changed_by.id if changed_by.present? && has_venue_column?(:reviewed_by_id)

        Venue.where(id: changed_ids).update_all(attributes)
      end
    end

    result = {
      selected_count: venue_ids.size,
      changed_count: changed_ids.size,
      unchanged_count: venue_ids.size - changed_ids.size,
      affected_place_ids: changed_ids,
      previous_categories: previous_categories,
      new_category: target,
      filters_used: filters,
      changed_by: changed_by&.id,
      changed_at: now.iso8601
    }
    log_reclassification(result, logger)
    result
  end

  private

  def apply_name_filter(relation)
    folded_terms(name_query).reduce(relation) do |current_relation, term|
      current_relation.where("#{folded_sql('venues.name')} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end
  end

  def apply_excluded_name_filter(relation)
    folded_terms(excluded_name_query).reduce(relation) do |current_relation, term|
      current_relation.where("#{folded_sql('venues.name')} NOT LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end
  end

  def apply_location_filter(relation, column_name, value)
    return relation if value.blank? || !has_venue_column?(column_name)

    folded_terms(value).reduce(relation) do |current_relation, term|
      current_relation.where("#{folded_sql("venues.#{quoted_column(column_name)}")} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end
  end

  def venue_ids_for_selection(selection_mode, selected_ids)
    case selection_mode.to_s
    when SELECTION_FILTERED
      raise ArgumentError, 'Aplica al menos un filtro antes de reclasificar todos los resultados.' unless filters_present?

      scope.pluck(:id)
    else
      ids = Array(selected_ids).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      return [] if ids.empty?

      scope.where(id: ids).pluck(:id)
    end
  end

  def normalized_categories(raw_categories)
    Array(raw_categories).flatten.map { |category| normalized_category(category) }.compact.uniq
  end

  def normalized_category(value)
    category = value.to_s.strip
    Venue::CATEGORIES.include?(category) ? category : nil
  end

  def normalized_free_text(value)
    value.to_s.strip.gsub(/\s+/, ' ').presence
  end

  def folded_terms(value)
    fold_text(value).scan(/[a-z0-9]+/)
  end

  def fold_text(value)
    value.to_s
         .strip
         .downcase
         .unicode_normalize(:nfkd)
         .encode('ASCII', replace: '', undef: :replace)
         .gsub(/\s+/, ' ')
  end

  def folded_sql(column_sql)
    ACCENT_REPLACEMENTS.reduce("LOWER(COALESCE(#{column_sql}, ''))") do |sql, (accented, replacement)|
      "REPLACE(#{sql}, '#{accented}', '#{replacement}')"
    end
  end

  def quoted_column(column_name)
    ActiveRecord::Base.connection.quote_column_name(column_name)
  end

  def group_count_if_available(relation, column_name)
    return {} unless has_venue_column?(column_name)

    relation.where.not(column_name => [nil, '']).group(column_name).count.sort_by { |_value, count| -count }
  end

  def google_linked_count(relation)
    return 0 unless has_venue_column?(:google_place_id)

    relation.where.not(google_place_id: [nil, '']).count
  end

  def has_venue_column?(column_name)
    Venue.column_names.include?(column_name.to_s)
  end

  def log_reclassification(result, logger)
    logger.info(
      JSON.generate(
        action: 'bulk_reclassify_black_coffee_places',
        affectedPlaceIds: result[:affected_place_ids],
        affectedCount: result[:changed_count],
        selectedCount: result[:selected_count],
        previousCategories: result[:previous_categories],
        newCategory: result[:new_category],
        filtersUsed: result[:filters_used],
        changedBy: result[:changed_by],
        changedAt: result[:changed_at]
      )
    )
  end
end
