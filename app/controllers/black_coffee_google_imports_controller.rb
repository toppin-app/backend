class BlackCoffeeGoogleImportsController < ApplicationController
  MAX_STORED_GOOGLE_ERROR_LENGTH = 1_000
  MAX_FLASH_ERROR_LENGTH = 700
  GLOBAL_GOOGLE_COUNT_ERROR_PATTERNS = [
    /API has not been used/i,
    /API key/i,
    /billing/i,
    /disabled/i,
    /location.*not supported/i,
    /not authorized/i,
    /PERMISSION_DENIED/i,
    /region.*not supported/i,
    /SERVICE_DISABLED/i,
    /unsupported region/i
  ].freeze

  before_action :check_admin
  before_action :ensure_regions_and_categories
  before_action :set_import_run, only: [:show, :approve_candidate, :reject_candidate, :approve_selected, :reject_selected]

  def index
    @title = 'Importador Google Maps'
    @regions = BlackCoffeeImportRegion.includes(:region_categories).ordered.to_a
    @categories = GooglePlacesBlackCoffeeClient.category_options
    @region_progress = progress_by_region(@regions)
    @overall_progress = aggregate_progress(@region_progress.values)
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
    flash[:alert] = compact_flash_errors(errors, prefix: 'Algunos candidatos no se pudieron aprobar:') if errors.any?

    redirect_to black_coffee_google_import_path(@import_run)
  end

  def reject_selected
    candidates = selected_candidates
    candidates.each(&:reject!)

    redirect_to black_coffee_google_import_path(@import_run), notice: "#{candidates.size} candidatos rechazados."
  end

  def refresh_region_google_counts
    region = BlackCoffeeImportRegion.includes(:region_categories).find(params[:region_id])
    client = GooglePlacesAggregateClient.new
    region_place, resolved_region_place = client.region_place_resource_name(region)
    requests_count = resolved_region_place ? 1 : 0
    successful_count = 0
    errors = []
    global_error = nil

    Venue::CATEGORIES.each_with_index do |category, index|
      region_category = BlackCoffeeImportRegionCategory.find_or_create_by!(
        black_coffee_import_region: region,
        category: category
      )
      requests_count += 1

      begin
        count = client.count_region_category(region_place: region_place, category: category)
        region_category.update!(
          google_total_count: count,
          google_total_counted_at: Time.current,
          google_total_count_error: nil
        )
        successful_count += 1
      rescue GooglePlacesAggregateClient::RequestError => e
        error_message = compact_google_error(e.message)
        region_category.update!(google_total_count_error: error_message)
        errors << "#{GooglePlacesBlackCoffeeClient.config_for(category)[:label]}: #{error_message}"

        next unless global_google_count_error?(error_message)

        global_error = error_message
        mark_remaining_categories_with_google_error(region, Venue::CATEGORIES[(index + 1)..-1], error_message)
        break
      end
    end

    message = "Totales Google actualizados para #{region.name}: #{successful_count}/#{Venue::CATEGORIES.size} categorias. Peticiones estimadas: #{requests_count}."
    flash[:notice] = message
    if global_error.present?
      flash[:alert] = "Google devolvio un error global y se detuvo el calculo para no repetir peticiones. Revisa el detalle en #{region.name}."
    elsif errors.any?
      flash[:alert] = "#{errors.size} categorias fallaron. Revisa las etiquetas rojas del progreso por categoria para ver el detalle."
    end

    redirect_to black_coffee_google_imports_path(anchor: "region-#{region.id}")
  rescue GooglePlacesAggregateClient::MissingApiKeyError, GooglePlacesAggregateClient::RequestError => e
    redirect_to black_coffee_google_imports_path(anchor: "region-#{params[:region_id]}"), alert: compact_google_error(e.message)
  rescue StandardError => e
    redirect_to black_coffee_google_imports_path(anchor: "region-#{params[:region_id]}"), alert: compact_flash_errors([e.message], prefix: 'No se pudieron calcular los totales Google:')
  end

  private

  def import_params
    params.permit(:region_id, :category, :limit, :query_override)
  end

  def compact_flash_errors(errors, prefix:)
    details = errors.first(3).map { |error| error.to_s.squish.truncate(180) }.join(' | ')
    remaining = errors.size - 3
    message = "#{prefix} #{details}"
    message += " | #{remaining} errores mas." if remaining.positive?
    message.truncate(MAX_FLASH_ERROR_LENGTH)
  end

  def compact_google_error(message)
    message.to_s.squish.truncate(MAX_STORED_GOOGLE_ERROR_LENGTH)
  end

  def global_google_count_error?(message)
    GLOBAL_GOOGLE_COUNT_ERROR_PATTERNS.any? { |pattern| message.match?(pattern) }
  end

  def mark_remaining_categories_with_google_error(region, categories, error_message)
    Array(categories).compact.each do |category|
      BlackCoffeeImportRegionCategory.find_or_create_by!(
        black_coffee_import_region: region,
        category: category
      ).update!(google_total_count_error: error_message)
    end
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

  def progress_by_region(regions)
    regions.each_with_object({}) do |region, progress|
      totals = aggregate_progress(region.region_categories)
      progress[region.id] = totals.merge(
        completion_percentage: completion_percentage(totals)
      )
    end
  end

  def aggregate_progress(records)
    records.each_with_object(empty_progress) do |record, totals|
      totals[:total_candidates] += progress_value(record, :total_candidates).to_i
      totals[:pending_count] += progress_value(record, :pending_count).to_i
      totals[:approved_count] += progress_value(record, :approved_count).to_i
      totals[:rejected_count] += progress_value(record, :rejected_count).to_i
      totals[:duplicate_count] += progress_value(record, :duplicate_count).to_i

      google_total_count = progress_value(record, :google_total_count)
      next if google_total_count.nil?

      totals[:google_total_count] += google_total_count.to_i
      google_approved_count = progress_value(record, :google_approved_count)
      google_counted_categories = progress_value(record, :google_counted_categories)
      totals[:google_approved_count] += google_approved_count.nil? ? progress_value(record, :approved_count).to_i : google_approved_count.to_i
      totals[:google_counted_categories] += google_counted_categories.nil? ? 1 : google_counted_categories.to_i
    end.tap do |totals|
      totals[:reviewed_count] = totals[:approved_count] + totals[:rejected_count] + totals[:duplicate_count]
      totals[:remaining_count] = totals[:pending_count]
      totals[:google_missing_count] = google_missing_count(totals)
      totals[:completion_percentage] = completion_percentage(totals)
    end
  end

  def empty_progress
    {
      total_candidates: 0,
      pending_count: 0,
      approved_count: 0,
      rejected_count: 0,
      duplicate_count: 0,
      google_total_count: 0,
      google_approved_count: 0,
      google_counted_categories: 0
    }
  end

  def completion_percentage(totals)
    denominator = totals[:google_total_count].to_i.positive? ? totals[:google_total_count].to_i : totals[:total_candidates].to_i
    return 0 if denominator.zero?

    numerator = totals[:google_total_count].to_i.positive? ? totals[:google_approved_count].to_i : totals[:approved_count].to_i
    ((numerator.to_f / denominator) * 100).round
  end

  def google_missing_count(totals)
    return nil unless totals[:google_total_count].to_i.positive?

    [totals[:google_total_count].to_i - totals[:google_approved_count].to_i, 0].max
  end

  def progress_value(record, key)
    if record.respond_to?(:has_attribute?)
      return record[key] if record.has_attribute?(key)
      return nil
    end

    record[key] if record.respond_to?(:[])
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
