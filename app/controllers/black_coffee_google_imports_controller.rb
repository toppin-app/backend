class BlackCoffeeGoogleImportsController < ApplicationController
  before_action :check_admin
  before_action :ensure_regions_and_categories
  before_action :set_import_run, only: [:show, :approve_candidate, :reject_candidate, :approve_selected, :reject_selected]

  def index
    @title = 'Importador Google Maps'
    @regions = BlackCoffeeImportRegion.includes(:region_categories).ordered
    @categories = GooglePlacesBlackCoffeeClient.category_options
    @recent_runs = BlackCoffeeImportRun.includes(:black_coffee_import_region)
                                      .order(created_at: :desc)
                                      .limit(12)
    @api_key_present = GooglePlacesBlackCoffeeClient.api_key.present?
  end

  def create
    region = BlackCoffeeImportRegion.find(import_params[:region_id])
    category = import_params[:category].to_s
    unless Venue::CATEGORIES.include?(category)
      redirect_to black_coffee_google_imports_path, alert: 'Categoria no valida para Black Coffee.' and return
    end

    limit = clamped_limit(import_params[:limit])
    region_category = BlackCoffeeImportRegionCategory.find_or_create_by!(
      black_coffee_import_region: region,
      category: category
    )
    config = GooglePlacesBlackCoffeeClient.config_for(category)
    import_run = BlackCoffeeImportRun.create!(
      black_coffee_import_region: region,
      black_coffee_import_region_category: region_category,
      category: category,
      query: import_params[:query_override].to_s.strip.presence || config.fetch(:query),
      google_types: Array(config[:google_types]),
      limit: limit,
      status: 'running'
    )

    begin
      candidates = GooglePlacesBlackCoffeeClient.new.search(
        region: region,
        category: category,
        limit: limit,
        query_override: import_params[:query_override]
      )
      candidates.each do |candidate_attrs|
        duplicate_venue = duplicate_venue_for(candidate_attrs)
        import_run.import_candidates.create!(
          candidate_attrs.merge(
            black_coffee_import_region: region,
            black_coffee_import_region_category: region_category,
            status: duplicate_venue.present? ? 'duplicate' : 'pending',
            duplicate_venue: duplicate_venue
          )
        )
      end

      import_run.update!(
        status: 'completed',
        found_count: candidates.size,
        candidate_count: candidates.size
      )
      region_category.update!(last_imported_at: Time.current)
      import_run.refresh_counts!

      redirect_to black_coffee_google_import_path(import_run), notice: 'Busqueda completada. Revisa los candidatos antes de guardar locales.'
    rescue GooglePlacesBlackCoffeeClient::MissingApiKeyError, GooglePlacesBlackCoffeeClient::RequestError => e
      import_run.update!(status: 'failed', error_message: e.message)
      import_run.refresh_counts!
      redirect_to black_coffee_google_imports_path, alert: e.message
    rescue StandardError => e
      import_run.update!(status: 'failed', error_message: e.message)
      import_run.refresh_counts!
      redirect_to black_coffee_google_imports_path, alert: "No se pudo completar la importacion: #{e.message}"
    end
  end

  def show
    @title = "Revision importacion ##{@import_run.id}"
    @candidates = @import_run.import_candidates.order(
      Arel.sql("CASE status WHEN 'pending' THEN 0 WHEN 'duplicate' THEN 1 WHEN 'approved' THEN 2 WHEN 'rejected' THEN 3 ELSE 4 END"),
      rating: :desc,
      name: :asc
    )
  end

  def approve_candidate
    candidate = candidate_from_run
    venue = candidate.approve!

    if candidate.duplicate?
      redirect_to black_coffee_google_import_path(@import_run), alert: "#{candidate.name} ya existe como #{venue.name}."
    else
      redirect_to black_coffee_google_import_path(@import_run), notice: "#{candidate.name} aprobado y creado como local."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to black_coffee_google_import_path(@import_run), alert: "No se pudo aprobar: #{e.record.errors.full_messages.to_sentence}"
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run), alert: "No se pudo aprobar: #{e.message}"
  end

  def reject_candidate
    candidate = candidate_from_run
    candidate.reject!

    redirect_to black_coffee_google_import_path(@import_run), notice: "#{candidate.name} rechazado."
  end

  def approve_selected
    candidates = selected_candidates
    approved_count = 0
    duplicate_count = 0
    errors = []

    candidates.each do |candidate|
      venue = candidate.approve!
      if candidate.duplicate?
        duplicate_count += 1
      elsif venue.present?
        approved_count += 1
      end
    rescue StandardError => e
      errors << "#{candidate.name}: #{e.message}"
    end

    message = "#{approved_count} aprobados"
    message += ", #{duplicate_count} duplicados" if duplicate_count.positive?
    flash[:notice] = message
    flash[:alert] = errors.join(' | ') if errors.any?

    redirect_to black_coffee_google_import_path(@import_run)
  end

  def reject_selected
    candidates = selected_candidates
    candidates.each(&:reject!)

    redirect_to black_coffee_google_import_path(@import_run), notice: "#{candidates.size} candidatos rechazados."
  end

  private

  def import_params
    params.permit(:region_id, :category, :limit, :query_override)
  end

  def clamped_limit(value)
    [[value.to_i, 1].max, GooglePlacesBlackCoffeeClient::MAX_RESULTS].min
  end

  def set_import_run
    @import_run = BlackCoffeeImportRun.includes(
      :black_coffee_import_region,
      :black_coffee_import_region_category,
      import_candidates: [:approved_venue, :duplicate_venue]
    ).find(params[:id])
  end

  def candidate_from_run
    @import_run.import_candidates.find(params[:candidate_id])
  end

  def selected_candidates
    ids = Array(params[:candidate_ids]).reject(&:blank?)
    return BlackCoffeeImportCandidate.none if ids.empty?

    @import_run.import_candidates.where(id: ids, status: 'pending')
  end

  def duplicate_venue_for(candidate_attrs)
    google_place_id = candidate_attrs[:google_place_id].to_s
    if google_place_id.present? && Venue.column_names.include?('google_place_id')
      venue = Venue.find_by(google_place_id: google_place_id)
      return venue if venue.present?
    end

    normalized_name = candidate_attrs[:name].to_s.strip.downcase
    normalized_city = candidate_attrs[:city].to_s.strip.downcase
    return if normalized_name.blank?

    scope = Venue.where('LOWER(name) = ?', normalized_name)
    scope = scope.where('LOWER(city) = ?', normalized_city) if normalized_city.present?
    scope.first
  end

  def ensure_regions_and_categories
    regions = [
      ['Andalucia', 'andalucia'],
      ['Aragon', 'aragon'],
      ['Asturias', 'asturias'],
      ['Islas Baleares', 'islas_baleares'],
      ['Canarias', 'canarias'],
      ['Cantabria', 'cantabria'],
      ['Castilla-La Mancha', 'castilla_la_mancha'],
      ['Castilla y Leon', 'castilla_y_leon'],
      ['Cataluna', 'cataluna'],
      ['Comunidad Valenciana', 'comunidad_valenciana'],
      ['Extremadura', 'extremadura'],
      ['Galicia', 'galicia'],
      ['Comunidad de Madrid', 'comunidad_de_madrid'],
      ['Region de Murcia', 'region_de_murcia'],
      ['Navarra', 'navarra'],
      ['Pais Vasco', 'pais_vasco'],
      ['La Rioja', 'la_rioja'],
      ['Ceuta', 'ceuta'],
      ['Melilla', 'melilla']
    ]

    regions.each_with_index do |(name, slug), index|
      region = BlackCoffeeImportRegion.find_or_create_by!(slug: slug) do |record|
        record.name = name
        record.country_code = 'ES'
        record.position = index
      end

      Venue::CATEGORIES.each do |category|
        BlackCoffeeImportRegionCategory.find_or_create_by!(
          black_coffee_import_region: region,
          category: category
        )
      end
    end
  end
end
