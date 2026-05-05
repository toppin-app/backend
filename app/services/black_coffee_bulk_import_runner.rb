require 'set'

class BlackCoffeeBulkImportRunner
  DEFAULT_MAX_DEPTH = 8
  DEFAULT_MIN_CELL_SIZE_METERS = 1_500
  DEFAULT_STEP_BUDGET = 2
  DEFAULT_TIME_BUDGET_SECONDS = 8
  FATAL_ERROR_PATTERNS = [
    /API has not been used/i,
    /API key/i,
    /API_KEY_SERVICE_BLOCKED/i,
    /billing/i,
    /disabled/i,
    /not authorized/i,
    /PERMISSION_DENIED/i,
    /quota/i,
    /rate limit/i,
    /RESOURCE_EXHAUSTED/i,
    /SERVICE_DISABLED/i
  ].freeze

  def self.start!(region:, categories: GooglePlacesBlackCoffeeClient.importable_categories)
    active_import = region.bulk_imports.active.recent_first.first
    return active_import if active_import.present?

    bounds = GooglePlacesRegionBoundsResolver.new.resolve(region)
    geometry_strategy = bounds.delete(:strategy)

    ActiveRecord::Base.transaction do
      bulk_import = region.bulk_imports.create!(
        status: 'pending',
        geometry_strategy: geometry_strategy,
        categories_payload: categories,
        bounds_payload: bounds,
        max_depth: DEFAULT_MAX_DEPTH,
        min_cell_size_meters: DEFAULT_MIN_CELL_SIZE_METERS,
        step_limit: GooglePlacesBlackCoffeeClient::MAX_RESULTS
      )

      categories.each do |category|
        region_category = BlackCoffeeImportRegionCategory.find_or_create_by!(
          black_coffee_import_region: region,
          category: category
        )
        config = GooglePlacesBlackCoffeeClient.config_for(category)
        import_run = bulk_import.import_runs.create!(
          black_coffee_import_region: region,
          black_coffee_import_region_category: region_category,
          category: category,
          query: "Importacion total por celdas: #{config.fetch(:query)}",
          google_types: Array(config[:google_types]),
          limit: bulk_import.step_limit,
          status: 'running'
        )
        bulk_import.import_steps.create!(
          black_coffee_import_run: import_run,
          category: category,
          status: 'pending',
          depth: 0,
          south_latitude: bounds.dig(:low, :latitude) || bounds.dig('low', 'latitude'),
          south_longitude: bounds.dig(:low, :longitude) || bounds.dig('low', 'longitude'),
          north_latitude: bounds.dig(:high, :latitude) || bounds.dig('high', 'latitude'),
          north_longitude: bounds.dig(:high, :longitude) || bounds.dig('high', 'longitude')
        )
      end

      bulk_import.refresh_progress!
      region.update!(status: 'in_progress') if region.status != 'in_progress'
      bulk_import
    end
  end

  def self.advance!(bulk_import:, step_budget: DEFAULT_STEP_BUDGET, time_budget_seconds: DEFAULT_TIME_BUDGET_SECONDS)
    new(bulk_import).advance!(step_budget: step_budget, time_budget_seconds: time_budget_seconds)
  end

  def self.retry_failed!(bulk_import:)
    new(bulk_import).retry_failed!
  end

  def initialize(bulk_import, client: GooglePlacesBlackCoffeeClient.new)
    @bulk_import = bulk_import
    @client = client
  end

  def advance!(step_budget:, time_budget_seconds:)
    return @bulk_import if @bulk_import.finished?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    fatal_error = nil
    processed_steps = 0

    loop do
      break if processed_steps >= step_budget
      break if processed_steps.positive? && elapsed_seconds(started_at) >= time_budget_seconds

      step = claim_next_step
      break if step.blank?

      result = process_step(step)
      processed_steps += 1
      fatal_error = result[:fatal_error] if result[:fatal_error].present?
      break if fatal_error.present?
    end

    @bulk_import.reload
    if fatal_error.present?
      fail_bulk_import!(fatal_error)
    elsif @bulk_import.import_steps.where(status: %w[pending running]).none?
      finalize_finished_import!
    else
      @bulk_import.refresh_progress!
    end

    @bulk_import.reload
  end

  def retry_failed!
    failed_steps_scope = @bulk_import.import_steps.where(status: 'failed')
    raise 'No hay celdas fallidas para reintentar.' unless failed_steps_scope.exists?

    BlackCoffeeBulkImport.transaction do
      @bulk_import.lock!
      failed_run_ids = failed_steps_scope.pluck(:black_coffee_import_run_id).compact.uniq
      failed_steps_scope.update_all(
        status: 'pending',
        processed_at: nil,
        error_message: nil,
        updated_at: Time.current
      )
      @bulk_import.import_runs.where(id: failed_run_ids).update_all(
        status: 'running',
        error_message: nil,
        updated_at: Time.current
      )
      @bulk_import.update!(
        status: 'pending',
        finished_at: nil,
        error_message: nil,
        current_category: nil,
        current_cell_label: nil
      )
      @bulk_import.refresh_progress!
      @bulk_import.black_coffee_import_region.update!(status: 'in_progress') if @bulk_import.black_coffee_import_region.status != 'in_progress'
    end

    @bulk_import.reload
  end

  private

  def claim_next_step
    BlackCoffeeBulkImport.transaction do
      @bulk_import.lock!
      return nil unless @bulk_import.active?

      step = @bulk_import.import_steps.pending_first.first
      return nil if step.blank?

      @bulk_import.update!(
        status: 'running',
        started_at: @bulk_import.started_at || Time.current,
        last_advanced_at: Time.current,
        current_category: step.category,
        current_cell_label: step.bounds_label
      )
      step.update!(status: 'running')
      step
    end
  end

  def process_step(step)
    requests_count = 0
    response = @client.search(
      region: @bulk_import.black_coffee_import_region,
      category: step.category,
      limit: @bulk_import.step_limit,
      query_override: nil,
      location_restriction: { rectangle: step.bounds_payload },
      append_region_to_query: false,
      metadata: true
    )
    candidates = Array(response[:candidates])
    requests_count = response[:requests_count].to_i
    raw_places_count = response[:raw_places_count].to_i

    if should_split_step?(step, raw_places_count)
      create_child_steps!(step)
      step.update!(
        status: 'split',
        found_count: raw_places_count,
        request_count: step.request_count.to_i + requests_count,
        processed_at: Time.current
      )
      finalize_category_run_if_finished(step.category)
      @bulk_import.refresh_progress!
      return {}
    end

    import_stats = append_candidates_to_run(step, candidates)
    saturated = candidates.size >= @bulk_import.step_limit.to_i && !splittable_step?(step)
    step.update!(
      status: 'completed',
      found_count: raw_places_count,
      saved_count: import_stats[:saved_count],
      duplicate_count: import_stats[:duplicate_count],
      request_count: step.request_count.to_i + requests_count,
      saturated: saturated,
      processed_at: Time.current
    )
    finalize_category_run_if_finished(step.category)
    @bulk_import.refresh_progress!
    {}
  rescue GooglePlacesBlackCoffeeClient::MissingApiKeyError, GooglePlacesBlackCoffeeClient::RequestError => e
    step.update!(
      status: 'failed',
      request_count: step.request_count.to_i + [requests_count, 1].max,
      error_message: e.message.to_s.truncate(1_000),
      processed_at: Time.current
    )
    finalize_category_run_if_finished(step.category)
    @bulk_import.refresh_progress!
    { fatal_error: fatal_google_error?(e.message) ? e.message : nil }
  rescue StandardError => e
    step.update!(
      status: 'failed',
      request_count: step.request_count.to_i + requests_count,
      error_message: "No se pudo procesar la celda: #{e.message}".truncate(1_000),
      processed_at: Time.current
    )
    finalize_category_run_if_finished(step.category)
    @bulk_import.refresh_progress!
    {}
  end

  def append_candidates_to_run(step, candidates)
    import_run = step.black_coffee_import_run
    region_category = import_run.black_coffee_import_region_category
    place_ids = candidates.map { |candidate| candidate[:google_place_id].to_s.strip.presence }.compact
    existing_place_ids = Set.new(@bulk_import.import_candidates.where(google_place_id: place_ids).pluck(:google_place_id))

    saved_count = 0
    duplicate_count = 0

    candidates.each do |candidate_attrs|
      google_place_id = candidate_attrs[:google_place_id].to_s.strip.presence
      if google_place_id.present? && existing_place_ids.include?(google_place_id)
        duplicate_count += 1
        next
      end

      duplicate_venue = duplicate_venue_for(candidate_attrs)
      import_run.import_candidates.create!(
        candidate_attrs.merge(
          black_coffee_import_region: @bulk_import.black_coffee_import_region,
          black_coffee_import_region_category: region_category,
          status: duplicate_venue.present? ? 'duplicate' : 'pending',
          duplicate_venue: duplicate_venue
        )
      )
      existing_place_ids << google_place_id if google_place_id.present?
      saved_count += 1
      duplicate_count += 1 if duplicate_venue.present?
    end

    import_run.with_lock do
      import_run.update!(
        found_count: import_run.found_count.to_i + candidates.size
      )
    end
    region_category.update!(last_imported_at: Time.current)
    import_run.refresh_counts!

    {
      saved_count: saved_count,
      duplicate_count: duplicate_count
    }
  end

  def should_split_step?(step, candidate_count)
    candidate_count >= @bulk_import.step_limit.to_i && splittable_step?(step)
  end

  def splittable_step?(step)
    return false if step.depth.to_i >= @bulk_import.max_depth.to_i

    cell_height_meters(step) > @bulk_import.min_cell_size_meters.to_i ||
      cell_width_meters(step) > @bulk_import.min_cell_size_meters.to_i
  end

  def create_child_steps!(step)
    mid_latitude = (step.south_latitude.to_f + step.north_latitude.to_f) / 2.0
    mid_longitude = (step.south_longitude.to_f + step.north_longitude.to_f) / 2.0

    quadrants = [
      [step.south_latitude.to_f, step.south_longitude.to_f, mid_latitude, mid_longitude],
      [step.south_latitude.to_f, mid_longitude, mid_latitude, step.north_longitude.to_f],
      [mid_latitude, step.south_longitude.to_f, step.north_latitude.to_f, mid_longitude],
      [mid_latitude, mid_longitude, step.north_latitude.to_f, step.north_longitude.to_f]
    ]

    quadrants.each do |south_latitude, south_longitude, north_latitude, north_longitude|
      next if north_latitude <= south_latitude || north_longitude <= south_longitude

      @bulk_import.import_steps.create!(
        black_coffee_import_run: step.black_coffee_import_run,
        category: step.category,
        status: 'pending',
        depth: step.depth.to_i + 1,
        south_latitude: south_latitude,
        south_longitude: south_longitude,
        north_latitude: north_latitude,
        north_longitude: north_longitude
      )
    end
  end

  def finalize_category_run_if_finished(category)
    return if @bulk_import.import_steps.where(category: category, status: %w[pending running]).exists?

    run = @bulk_import.import_runs.find_by(category: category)
    return if run.blank?

    if @bulk_import.import_steps.where(category: category, status: 'failed').exists?
      run.update!(
        status: 'failed',
        error_message: failed_steps_summary(category: category)
      )
    elsif run.status != 'completed' || run.error_message.present?
      run.update!(
        status: 'completed',
        error_message: nil
      )
    end
  end

  def finalize_finished_import!
    if @bulk_import.import_steps.where(status: 'failed').exists?
      fail_bulk_import!(failed_steps_summary)
    else
      finalize_completed_import!
    end
  end

  def finalize_completed_import!
    BlackCoffeeBulkImport.transaction do
      @bulk_import.lock!
      @bulk_import.import_runs.where(status: 'running').update_all(status: 'completed', updated_at: Time.current)
      @bulk_import.update!(
        status: 'completed',
        finished_at: Time.current,
        current_category: nil,
        current_cell_label: nil
      )
      @bulk_import.refresh_progress!
      @bulk_import.black_coffee_import_region.refresh_status!
    end
    @bulk_import
  end

  def fail_bulk_import!(message)
    BlackCoffeeBulkImport.transaction do
      @bulk_import.lock!
      @bulk_import.import_steps.where(status: 'running').update_all(
        status: 'failed',
        error_message: message.to_s.truncate(1_000),
        processed_at: Time.current,
        updated_at: Time.current
      )
      pending_run_ids = @bulk_import.import_steps.where(status: %w[pending failed]).pluck(:black_coffee_import_run_id).compact.uniq
      @bulk_import.import_runs.where(id: pending_run_ids, status: 'running').update_all(
        status: 'failed',
        error_message: message.to_s.truncate(1_000),
        updated_at: Time.current
      )
      @bulk_import.update!(
        status: 'failed',
        finished_at: Time.current,
        error_message: message.to_s.truncate(1_000)
      )
      @bulk_import.refresh_progress!
    end
    @bulk_import
  end

  def failed_steps_summary(category: nil)
    scope = @bulk_import.import_steps.where(status: 'failed')
    scope = scope.where(category: category) if category.present?

    messages = scope.order(updated_at: :desc).limit(3).pluck(:error_message).map { |value| value.to_s.strip }.reject(&:blank?).uniq
    return 'Algunas celdas no pudieron procesarse durante la importacion total.' if messages.blank?

    messages.join(' | ').truncate(1_000)
  end

  def fatal_google_error?(message)
    FATAL_ERROR_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
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

  def cell_height_meters(step)
    (step.north_latitude.to_f - step.south_latitude.to_f).abs * 111_320.0
  end

  def cell_width_meters(step)
    latitude = ((step.south_latitude.to_f + step.north_latitude.to_f) / 2.0) * Math::PI / 180.0
    meters_per_degree = 111_320.0 * [Math.cos(latitude).abs, 0.15].max
    (step.north_longitude.to_f - step.south_longitude.to_f).abs * meters_per_degree
  end

  def elapsed_seconds(started_at)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end
end
