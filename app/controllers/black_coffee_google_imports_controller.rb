class BlackCoffeeGoogleImportsController < ApplicationController
  ALL_CATEGORIES_VALUE = '__all__'.freeze
  DEFAULT_CANDIDATES_PER_PAGE = 100
  MAX_CANDIDATES_PER_PAGE = 250
  CANDIDATES_PER_PAGE_OPTIONS = [50, 100, 200, 250].freeze
  MAX_STORED_GOOGLE_ERROR_LENGTH = 1_000
  MAX_STORED_GOOGLE_ERROR_DETAILS_LENGTH = 20_000
  MAX_FLASH_ERROR_LENGTH = 700
  GLOBAL_GOOGLE_COUNT_ERROR_PATTERNS = [
    /API has not been used/i,
    /API key/i,
    /API_KEY_SERVICE_BLOCKED/i,
    /billing/i,
    /disabled/i,
    /location.*not supported/i,
    /not authorized/i,
    /PERMISSION_DENIED/i,
    /quota/i,
    /rate limit/i,
    /region.*not supported/i,
    /RESOURCE_EXHAUSTED/i,
    /SERVICE_DISABLED/i,
    /unsupported region/i
  ].freeze

  before_action :check_admin
  before_action :ensure_regions_and_categories
  before_action :set_import_run, only: [
    :show,
    :destroy,
    :approve_candidate,
    :reject_candidate,
    :approve_selected,
    :approve_all_pending,
    :reject_selected,
    :refresh_selected_images,
    :refresh_all_missing_images,
    :retry_approval_batch,
    :approval_status,
    :advance_approval,
    :retry_image_refresh,
    :image_refresh_status,
    :advance_image_refresh
  ]

  def index
    @title = 'Importador Google Maps'
    @regions = BlackCoffeeImportRegion.includes(:region_categories).ordered.to_a
    @categories = GooglePlacesBlackCoffeeClient.category_options
    @category_options = @categories + [["Todas las categorias (modo rapido: #{GooglePlacesBlackCoffeeClient.importable_categories.size} busquedas)", ALL_CATEGORIES_VALUE]]
    @all_categories_value = ALL_CATEGORIES_VALUE
    @importable_categories = GooglePlacesBlackCoffeeClient.importable_categories
    @region_progress = progress_by_region(@regions, @importable_categories)
    @overall_progress = aggregate_progress(@region_progress.values)
    bulk_imports = BlackCoffeeBulkImport.includes(:black_coffee_import_region).recent_first.to_a
    active_bulk_imports = bulk_imports.select(&:active?)
    @active_bulk_imports_by_region = active_bulk_imports.group_by(&:black_coffee_import_region_id).transform_values(&:first)
    @latest_bulk_imports_by_region = bulk_imports.group_by(&:black_coffee_import_region_id).transform_values(&:first)
    @recent_runs = BlackCoffeeImportRun.includes(:black_coffee_import_region)
                                      .where(category: @importable_categories)
                                      .order(created_at: :desc)
                                      .limit(12)
    @api_key_present = GooglePlacesBlackCoffeeClient.api_key.present?
  end

  def create
    region = BlackCoffeeImportRegion.find(import_params[:region_id])
    category = import_params[:category].to_s
    limit = clamped_limit(import_params[:limit])

    if category == ALL_CATEGORIES_VALUE
      create_region_import(region, limit)
      return
    end

    unless GooglePlacesBlackCoffeeClient.importable_categories.include?(category)
      redirect_to black_coffee_google_imports_path, alert: 'Categoria no valida para Black Coffee.' and return
    end

    result = import_category_for_region(
      region: region,
      category: category,
      limit: limit,
      query_override: import_params[:query_override]
    )

    if result[:success]
      redirect_to black_coffee_google_import_path(result[:import_run]), notice: 'Busqueda completada. Revisa los candidatos antes de guardar locales.'
    else
      redirect_to black_coffee_google_imports_path, alert: result[:error]
    end
  end

  def create_region_import(region, limit)
    results = GooglePlacesBlackCoffeeClient.importable_categories.map do |category|
      import_category_for_region(region: region, category: category, limit: limit, query_override: nil)
    end

    successful_results = results.select { |result| result[:success] }
    failed_results = results.reject { |result| result[:success] }
    found_count = successful_results.sum { |result| result[:found_count].to_i }
    candidates_count = successful_results.sum { |result| result[:candidate_count].to_i }

    flash[:notice] = "Importacion completa ejecutada para #{region.name}: #{successful_results.size}/#{results.size} categorias completadas, #{found_count} encontrados y #{candidates_count} candidatos guardados."
    if failed_results.any?
      flash[:alert] = compact_flash_errors(
        failed_results.map { |result| "#{GooglePlacesBlackCoffeeClient.config_for(result[:category])[:label]}: #{result[:error]}" },
        prefix: 'Algunas categorias fallaron:'
      )
    end

    redirect_to black_coffee_google_imports_path(anchor: "region-#{region.id}")
  end

  def import_category_for_region(region:, category:, limit:, query_override:)
    region_category = BlackCoffeeImportRegionCategory.find_or_create_by!(
      black_coffee_import_region: region,
      category: category
    )
    config = GooglePlacesBlackCoffeeClient.config_for(category)
    import_run = BlackCoffeeImportRun.create!(
      black_coffee_import_region: region,
      black_coffee_import_region_category: region_category,
      category: category,
      query: query_override.to_s.strip.presence || config.fetch(:query),
      google_types: Array(config[:google_types]),
      limit: limit,
      status: 'running'
    )

    candidates = GooglePlacesBlackCoffeeClient.new.search(
      region: region,
      category: category,
      limit: limit,
      query_override: query_override
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

    {
      success: true,
      category: category,
      import_run: import_run,
      found_count: candidates.size,
      candidate_count: import_run.import_candidates.count
    }
  rescue GooglePlacesBlackCoffeeClient::MissingApiKeyError, GooglePlacesBlackCoffeeClient::RequestError => e
    mark_import_run_failed(import_run, e.message)
    { success: false, category: category, import_run: import_run, error: e.message }
  rescue StandardError => e
    error_message = "No se pudo completar la importacion: #{e.message}"
    mark_import_run_failed(import_run, error_message)
    { success: false, category: category, import_run: import_run, error: error_message }
  end

  def show
    @title = "Candidatos importados #{@import_run.black_coffee_import_region.name} · #{run_category_label} · corrida ##{@import_run.id}"
    @per_page_options = CANDIDATES_PER_PAGE_OPTIONS
    @per_page = per_page_param
    @total_candidates = @import_run.candidate_count.to_i.positive? ? @import_run.candidate_count.to_i : @import_run.import_candidates.count
    @total_pages = [(@total_candidates.to_f / @per_page).ceil, 1].max
    @page = [[page_param, 1].max, @total_pages].min
    @pending_candidates_count = [
      @total_candidates - @import_run.approved_count.to_i - @import_run.duplicate_count.to_i - @import_run.rejected_count.to_i,
      0
    ].max
    @missing_image_candidates_count = @import_run.import_candidates.missing_images.count
    @refreshable_missing_image_candidates_count = @import_run.import_candidates.missing_images.image_refreshable.count
    @visible_candidates_from = @total_candidates.zero? ? 0 : ((@page - 1) * @per_page) + 1
    @visible_candidates_to = [@page * @per_page, @total_candidates].min
    @candidates = ordered_candidates_scope
                  .offset((@page - 1) * @per_page)
                  .limit(@per_page)
                  .includes(:approved_venue, :duplicate_venue)
    @latest_image_refresh_batch = @import_run.photo_refresh_batches.recent_first.first
    @image_refresh_progress_payload = @latest_image_refresh_batch&.as_progress_json
    @latest_approval_batch = latest_approval_batch
    @approval_progress_payload = @latest_approval_batch&.as_progress_json
  end

  def destroy
    if @import_run.import_candidates.where(status: 'approved').exists?
      redirect_to black_coffee_google_import_path(@import_run), alert: 'Esta corrida ya tiene locales aprobados. No la borro automaticamente para no dejar locales publicados sin trazabilidad.'
      return
    end

    run_id = @import_run.id
    candidate_count = @import_run.import_candidates.count
    @import_run.destroy_with_candidates!

    redirect_to black_coffee_google_imports_path, notice: "Corrida ##{run_id} eliminada. Se borraron #{candidate_count} candidatos y se recalculo el progreso."
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to import_run_fallback_path(@import_run), alert: e.message
  rescue StandardError => e
    redirect_to import_run_fallback_path(@import_run), alert: "No se pudo eliminar la corrida: #{e.message}"
  end

  def audit
    @title = 'Auditoria importador Google'
    @api_key_present = GooglePlacesAggregateClient.api_key.present?
    @live_google_enabled = ActiveModel::Type::Boolean.new.cast(params[:live_google])
    requested_live_scope = params[:live_scope].presence || 'smart'
    @live_scope = BlackCoffeeGoogleImportAudit::LIVE_SCOPES.include?(requested_live_scope) ? requested_live_scope : 'smart'
    requested_live_limit = params[:live_limit].presence || BlackCoffeeGoogleImportAudit::DEFAULT_LIVE_LIMIT
    @live_limit = [[requested_live_limit.to_i, 1].max, BlackCoffeeGoogleImportAudit::MAX_LIVE_LIMIT].min
    @audit_report = BlackCoffeeGoogleImportAudit.new(
      live_google: @live_google_enabled,
      live_scope: @live_scope,
      live_limit: @live_limit
    ).call
    @audit_json = JSON.pretty_generate(@audit_report)
  end

  def approve_candidate
    candidate = candidate_from_run
    unless candidate.pending?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: 'Este candidato ya fue revisado.'
      return
    end

    venue = candidate.approve!(refresh_counts: false)
    if candidate.duplicate?
      @import_run.apply_review_deltas!(duplicate_delta: 1)
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "#{candidate.name} ya existe como #{venue.name}."
    else
      @import_run.apply_review_deltas!(approved_delta: 1)
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: "#{candidate.name} aprobado y creado como local."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo aprobar: #{e.record.errors.full_messages.to_sentence}"
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo aprobar: #{e.message}"
  end

  def reject_candidate
    candidate = candidate_from_run
    unless candidate.pending?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: 'Este candidato ya fue revisado.'
      return
    end

    candidate.reject!(refresh_counts: false)
    @import_run.apply_review_deltas!(rejected_delta: 1)

    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: "#{candidate.name} rechazado."
  end

  def approve_selected
    existing_batch = latest_approval_batch
    if existing_batch&.active?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: 'Ya hay una aprobacion en curso para esta corrida. Puedes seguir el progreso desde aqui.'
      return
    end

    candidate_ids = selected_candidates.pluck(:id)
    if candidate_ids.blank?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: 'Selecciona al menos un candidato pendiente para aprobar.'
      return
    end

    batch = BlackCoffeeImportApprovalRunner.start_selected!(import_run: @import_run, candidate_ids: candidate_ids)
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: "Aprobacion preparada para #{batch.total_candidates_count} candidatos. Iremos publicandolos por bloques cortos para no saturar el servidor."
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo preparar la aprobacion masiva: #{e.message}"
  end

  def approve_all_pending
    existing_batch = latest_approval_batch
    if existing_batch&.active?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: 'Ya hay una aprobacion en curso para esta corrida. Puedes seguir el progreso desde aqui.'
      return
    end

    batch = BlackCoffeeImportApprovalRunner.start_pending_scope!(import_run: @import_run)
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: "Aprobacion total preparada para #{batch.total_candidates_count} pendientes. El dashboard los ira aprobando por lotes estables."
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo preparar la aprobacion total: #{e.message}"
  end

  def reject_selected
    candidates = selected_candidates
    if candidates.blank?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: 'Selecciona al menos un candidato pendiente para rechazar.'
      return
    end

    rejected_count = candidates.update_all(status: 'rejected', reviewed_at: Time.current)
    @import_run.apply_review_deltas!(rejected_delta: rejected_count)

    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: "#{rejected_count} candidatos rechazados."
  end

  def refresh_selected_images
    existing_batch = @import_run.photo_refresh_batches.active.recent_first.first
    if existing_batch.present?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: 'Ya hay un reintento de imagenes en curso para esta corrida. Puedes seguirlo desde aqui.'
      return
    end

    candidates = selected_candidates_for_image_refresh
    if candidates.blank?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: 'Selecciona al menos un candidato para reintentar sus imagenes.'
      return
    end

    selected_ids = candidates.ids
    selected_count = selected_ids.size
    batch = BlackCoffeeImportPhotoRefreshRunner.start!(
      import_run: @import_run,
      candidate_ids: selected_ids
    )
    skipped_count = [selected_count - batch.total_candidates_count.to_i, 0].max
    notice = "Reintento de imagenes preparado para #{batch.total_candidates_count} candidatos."
    if skipped_count.positive?
      notice += " Se omitieron #{skipped_count} que ya tenian imagen o no tenian datos suficientes de Google para refrescarlas."
    end
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: notice
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo preparar el reintento de imagenes: #{e.message}"
  end

  def refresh_all_missing_images
    existing_batch = @import_run.photo_refresh_batches.active.recent_first.first
    if existing_batch.present?
      redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: 'Ya hay un reintento de imagenes en curso para esta corrida. Puedes seguirlo desde aqui.'
      return
    end

    missing_count = @import_run.import_candidates.missing_images.count
    batch = BlackCoffeeImportPhotoRefreshRunner.start_missing_images_scope!(import_run: @import_run)
    skipped_count = [missing_count - batch.total_candidates_count.to_i, 0].max

    notice = "Reintento total de imagenes preparado para #{batch.total_candidates_count} candidatos sin foto."
    if skipped_count.positive?
      notice += " Se omitieron #{skipped_count} porque no tenian datos suficientes de Google para refrescarlas."
    end

    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: notice
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo preparar el reintento total de imagenes: #{e.message}"
  end

  def retry_image_refresh
    batch = latest_image_refresh_batch!
    BlackCoffeeImportPhotoRefreshRunner.retry_failed!(batch: batch)
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: 'Reintentaremos las imagenes que quedaron pendientes o fallaron.'
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo reanudar el reintento de imagenes: #{e.message}"
  end

  def image_refresh_status
    batch = latest_image_refresh_batch
    render json: batch.present? ? batch.as_progress_json : {}
  end

  def retry_approval_batch
    batch = latest_approval_batch!
    BlackCoffeeImportApprovalRunner.retry_failed!(batch: batch)
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), notice: 'Reintentaremos solo las aprobaciones que quedaron pendientes o fallaron.'
  rescue StandardError => e
    redirect_to black_coffee_google_import_path(@import_run, redirect_pagination_params), alert: "No se pudo reanudar la aprobacion: #{e.message}"
  end

  def approval_status
    batch = latest_approval_batch
    render json: batch.present? ? batch.as_progress_json : {}
  end

  def advance_approval
    batch = latest_approval_batch!
    BlackCoffeeImportApprovalRunner.advance!(batch: batch)
    render json: batch.reload.as_progress_json
  rescue StandardError => e
    batch = latest_approval_batch
    render json: (batch.present? ? batch.reload.as_progress_json : {}).merge(errorMessage: e.message), status: :unprocessable_entity
  end

  def advance_image_refresh
    batch = latest_image_refresh_batch!
    BlackCoffeeImportPhotoRefreshRunner.advance!(batch: batch)
    render json: batch.reload.as_progress_json
  rescue StandardError => e
    batch = latest_image_refresh_batch
    render json: (batch.present? ? batch.reload.as_progress_json : {}).merge(errorMessage: e.message), status: :unprocessable_entity
  end

  def refresh_region_google_counts
    region = BlackCoffeeImportRegion.includes(:region_categories).find(params[:region_id])
    result = refresh_google_counts_for_region(region)

    message = "Totales Google actualizados para #{region.name}: #{result[:successful_count]}/#{result[:total_categories]} categorias. Peticiones estimadas: #{result[:requests_count]}."
    message += ' Se uso circulo aproximado porque Google no soporta la geometria regional.' if result[:switched_to_circle]
    flash[:notice] = message
    if result[:global_error].present?
      flash[:alert] = "Google devolvio un error global y se detuvo el calculo para no repetir peticiones. Revisa el detalle en #{region.name}."
    elsif result[:errors].any?
      flash[:alert] = "#{result[:errors].size} categorias fallaron. Revisa las etiquetas rojas del progreso por categoria para ver el detalle."
    end

    redirect_to black_coffee_google_imports_path(anchor: "region-#{region.id}")
  rescue GooglePlacesAggregateClient::MissingApiKeyError, GooglePlacesAggregateClient::RequestError => e
    redirect_to black_coffee_google_imports_path(anchor: "region-#{params[:region_id]}"), alert: compact_google_error(e.message)
  rescue StandardError => e
    redirect_to black_coffee_google_imports_path(anchor: "region-#{params[:region_id]}"), alert: compact_flash_errors([e.message], prefix: 'No se pudieron calcular los totales Google:')
  end

  def refresh_all_region_google_counts
    regions = BlackCoffeeImportRegion.includes(:region_categories).ordered.to_a
    importable_categories = GooglePlacesBlackCoffeeClient.importable_categories
    client = GooglePlacesAggregateClient.new
    totals = {
      regions_count: 0,
      successful_count: 0,
      total_categories: regions.size * importable_categories.size,
      requests_count: 0,
      failed_regions: [],
      switched_regions: [],
      global_error: nil
    }

    regions.each do |region|
      result = refresh_google_counts_for_region(region, client: client, importable_categories: importable_categories)
      totals[:regions_count] += 1
      totals[:successful_count] += result[:successful_count]
      totals[:requests_count] += result[:requests_count]
      totals[:failed_regions] << region.name if result[:errors].any? || result[:global_error].present?
      totals[:switched_regions] << region.name if result[:switched_to_circle]

      next if result[:global_error].blank?

      totals[:global_error] = result[:global_error]
      break
    end

    message = "Totales Google recalculados: #{totals[:successful_count]}/#{totals[:total_categories]} categorias en #{totals[:regions_count]}/#{regions.size} comunidades. Peticiones estimadas: #{totals[:requests_count]}."
    message += " Fallback circular: #{totals[:switched_regions].join(', ')}." if totals[:switched_regions].any?
    flash[:notice] = message

    if totals[:global_error].present?
      flash[:alert] = "Google devolvio un error global y se detuvo el recalculo masivo para no repetir peticiones. Ultima region con fallo: #{totals[:failed_regions].last}."
    elsif totals[:failed_regions].any?
      flash[:alert] = "Algunas comunidades tuvieron errores: #{totals[:failed_regions].first(6).join(', ')}#{totals[:failed_regions].size > 6 ? '...' : ''}. Revisa las etiquetas rojas."
    end

    redirect_to black_coffee_google_imports_path
  rescue GooglePlacesAggregateClient::MissingApiKeyError, GooglePlacesAggregateClient::RequestError => e
    redirect_to black_coffee_google_imports_path, alert: compact_google_error(e.message)
  rescue StandardError => e
    redirect_to black_coffee_google_imports_path, alert: compact_flash_errors([e.message], prefix: 'No se pudieron recalcular todos los totales Google:')
  end

  private

  def mark_import_run_failed(import_run, message)
    return if import_run.blank?

    import_run.update!(
      status: 'failed',
      error_message: message.to_s.squish.truncate(MAX_STORED_GOOGLE_ERROR_LENGTH)
    )
    import_run.refresh_counts!
  end

  def import_params
    params.permit(:region_id, :category, :limit, :query_override)
  end

  def refresh_google_counts_for_region(region, client: GooglePlacesAggregateClient.new, importable_categories: GooglePlacesBlackCoffeeClient.importable_categories)
    result = {
      successful_count: 0,
      total_categories: importable_categories.size,
      requests_count: 0,
      errors: [],
      global_error: nil,
      switched_to_circle: false
    }

    region_place = nil
    begin
      unless client.circle_fallback_enabled?(region)
        result[:requests_count] += 1 if region.google_region_resource_name.blank?
        region_place, = client.region_place_resource_name(region)
      end
    rescue GooglePlacesAggregateClient::RequestError => e
      error_message = compact_google_error(e.message)
      error_details = compact_google_error_details(e.details)
      mark_remaining_categories_with_google_error(region, importable_categories, error_message, error_details)
      result[:errors] << error_message
      result[:global_error] = error_message if global_google_count_error?(error_message)
      return result
    end

    importable_categories.each_with_index do |category, index|
      region_category = BlackCoffeeImportRegionCategory.find_or_create_by!(
        black_coffee_import_region: region,
        category: category
      )
      result[:requests_count] += 1

      begin
        count = client.count_region_category(region: region, region_place: region_place, category: category)
        update_region_category_google_success(region_category, count)
        result[:successful_count] += 1
      rescue GooglePlacesAggregateClient::RequestError => e
        if retry_with_circle_fallback?(client, region, e)
          client.enable_circle_fallback!(region, e)
          region.reload
          result[:switched_to_circle] = true
          result[:requests_count] += 1

          begin
            count = client.count_region_category(region: region, region_place: nil, category: category)
            update_region_category_google_success(region_category, count)
            result[:successful_count] += 1
            next
          rescue GooglePlacesAggregateClient::RequestError => fallback_error
            e = fallback_error
          end
        end

        error_message = compact_google_error(e.message)
        error_details = compact_google_error_details(e.details)
        update_region_category_google_error(region_category, error_message, error_details)
        result[:errors] << "#{GooglePlacesBlackCoffeeClient.config_for(category)[:label]}: #{error_message}"

        next unless global_google_count_error?(error_message)

        result[:global_error] = error_message
        mark_remaining_categories_with_google_error(region, importable_categories[(index + 1)..-1], error_message, error_details)
        break
      end
    end

    result
  end

  def update_region_category_google_success(region_category, count)
    attributes = {
      google_total_count: count,
      google_total_counted_at: Time.current,
      google_total_count_error: nil
    }
    if region_category.has_attribute?(:google_total_count_error_details)
      attributes[:google_total_count_error_details] = nil
    end
    region_category.update!(attributes)
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

  def compact_google_error_details(message)
    message.to_s.truncate(MAX_STORED_GOOGLE_ERROR_DETAILS_LENGTH)
  end

  def global_google_count_error?(message)
    GLOBAL_GOOGLE_COUNT_ERROR_PATTERNS.any? { |pattern| message.match?(pattern) }
  end

  def retry_with_circle_fallback?(client, region, error)
    client.unsupported_region_geometry_error?(error) &&
      client.circle_fallback_available?(region) &&
      !client.circle_fallback_enabled?(region)
  end

  def mark_remaining_categories_with_google_error(region, categories, error_message, error_details)
    Array(categories).compact.each do |category|
      region_category = BlackCoffeeImportRegionCategory.find_or_create_by!(
        black_coffee_import_region: region,
        category: category
      )
      update_region_category_google_error(region_category, error_message, error_details)
    end
  end

  def update_region_category_google_error(region_category, error_message, error_details)
    attributes = { google_total_count_error: error_message }
    if region_category.has_attribute?(:google_total_count_error_details)
      attributes[:google_total_count_error_details] = error_details
    end
    region_category.update!(attributes)
  end

  def clamped_limit(value)
    [[value.to_i, 1].max, GooglePlacesBlackCoffeeClient::MAX_RESULTS].min
  end

  def set_import_run
    @import_run = BlackCoffeeImportRun.includes(
      :black_coffee_import_region,
      :black_coffee_import_region_category
    ).find(params[:id])
  end

  def candidate_from_run
    @import_run.import_candidates.find(params[:candidate_id])
  end

  def latest_image_refresh_batch
    @import_run.photo_refresh_batches.recent_first.first
  end

  def latest_image_refresh_batch!
    latest_image_refresh_batch || raise('No hay ningun lote de reintento de imagenes para esta corrida.')
  end

  def latest_approval_batch
    @import_run.approval_batches.recent_first.first
  end

  def latest_approval_batch!
    latest_approval_batch || raise('No hay ningun lote de aprobacion para esta corrida.')
  end

  def import_run_fallback_path(import_run)
    import_run&.persisted? ? black_coffee_google_import_path(import_run) : black_coffee_google_imports_path
  end

  def selected_candidates
    ids = Array(params[:candidate_ids]).reject(&:blank?)
    return BlackCoffeeImportCandidate.none if ids.empty?

    @import_run.import_candidates.where(id: ids, status: 'pending')
  end

  def selected_candidates_for_image_refresh
    ids = Array(params[:candidate_ids]).reject(&:blank?)
    return BlackCoffeeImportCandidate.none if ids.empty?

    @import_run.import_candidates.where(id: ids)
  end

  def run_category_label
    GooglePlacesBlackCoffeeClient::CATEGORY_CONFIG.dig(@import_run.category, :label) || @import_run.category
  end

  def ordered_candidates_scope
    @import_run.import_candidates.order(
      Arel.sql("CASE status WHEN 'pending' THEN 0 WHEN 'duplicate' THEN 1 WHEN 'approved' THEN 2 WHEN 'rejected' THEN 3 ELSE 4 END"),
      rating: :desc,
      name: :asc
    )
  end

  def page_param
    value = params[:page].to_i
    value.positive? ? value : 1
  end

  def per_page_param
    value = params[:per_page].to_i
    return DEFAULT_CANDIDATES_PER_PAGE if value <= 0

    [value, MAX_CANDIDATES_PER_PAGE].min
  end

  def redirect_pagination_params
    {
      page: params[:page].presence,
      per_page: params[:per_page].presence
    }.compact
  end

  def progress_by_region(regions, categories)
    regions.each_with_object({}) do |region, progress|
      region_categories = region.region_categories.select { |region_category| categories.include?(region_category.category) }
      totals = aggregate_progress(region_categories)
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

      GooglePlacesBlackCoffeeClient.importable_categories.each do |category|
        BlackCoffeeImportRegionCategory.find_or_create_by!(
          black_coffee_import_region: region,
          category: category
        )
      end
    end
  end
end
