class BlackCoffeeGoogleImportAudit
  STALE_AFTER = 14.days
  SEVERITIES = %i[critical warning info].freeze
  LIVE_SCOPES = %w[smart issues all].freeze
  DEFAULT_LIVE_LIMIT = 20
  MAX_LIVE_LIMIT = 200
  MAX_LIVE_ERROR_DETAILS_LENGTH = 20_000

  attr_reader :regions, :categories, :category_labels

  def initialize(
    regions: BlackCoffeeImportRegion.includes(:region_categories).ordered.to_a,
    categories: GooglePlacesBlackCoffeeClient.importable_categories,
    live_google: false,
    live_scope: 'smart',
    live_limit: DEFAULT_LIVE_LIMIT
  )
    @regions = regions
    @categories = categories
    @category_labels = GooglePlacesBlackCoffeeClient.category_options.to_h.invert
    @live_google = ActiveModel::Type::Boolean.new.cast(live_google)
    @live_scope = LIVE_SCOPES.include?(live_scope.to_s) ? live_scope.to_s : 'smart'
    @live_limit = [[live_limit.to_i, 1].max, MAX_LIVE_LIMIT].min
    @region_place_cache = {}
  end

  def call
    issues = []
    summaries = regions.map { |region| audit_region(region, issues) }
    live_google_report = audit_live_google(summaries, issues)
    totals = build_totals(summaries, issues)

    {
      generated_at: Time.current,
      categories: categories,
      category_labels: category_labels,
      live_google: live_google_report,
      summaries: summaries,
      totals: totals,
      issues: issues,
      recommendations: recommendations_for(issues)
    }
  end

  private

  def audit_region(region, issues)
    states_by_category = region.region_categories.index_by(&:category)
    category_summaries = categories.map do |category|
      state = states_by_category[category]
      audit_region_category(region, category, state, issues)
    end

    audit_region_shape(region, issues)
    audit_excluded_categories(region, states_by_category, issues)
    audit_category_distribution(region, category_summaries, issues)

    google_total = category_summaries.sum { |summary| summary[:google_total_count].to_i }
    approved = category_summaries.sum { |summary| summary[:approved_count].to_i }
    counted_categories = category_summaries.count { |summary| summary[:google_total_known] }

    {
      region: region_payload(region),
      strategy: region.has_attribute?(:google_count_location_strategy) ? region.google_count_location_strategy : 'region',
      google_total_count: google_total,
      approved_count: approved,
      missing_vs_google: google_total.positive? ? [google_total - approved, 0].max : nil,
      percentage: google_total.positive? ? ((approved.to_f / google_total) * 100).round : 0,
      counted_categories: counted_categories,
      expected_categories: categories.size,
      categories: category_summaries
    }
  end

  def audit_region_category(region, category, state, issues)
    label = label_for(category)
    unless state
      add_issue(issues, :critical, region, category, 'Falta la fila de seguimiento para esta categoria importable.', 'Ejecutar ensure/importador o crear la fila antes de recalcular.')
      return empty_category_summary(category, label)
    end

    actual_counts = actual_candidate_counts(state)
    stored_counts = stored_candidate_counts(state)
    if actual_counts != stored_counts
      add_issue(
        issues,
        :warning,
        region,
        category,
        "Los contadores internos no coinciden con los candidatos reales. Guardado: #{stored_counts.inspect}. Real: #{actual_counts.inspect}.",
        'Ejecutar refresh_counts! para esta categoria antes de interpretar pendientes/aprobados.'
      )
    end

    if state.google_total_count_error.present?
      add_issue(issues, :critical, region, category, "Google devolvio error: #{state.google_total_count_error}", 'Revisar el detalle tecnico y recalcular esta comunidad/categoria.')
    elsif !state.google_total_known?
      add_issue(issues, :critical, region, category, 'No hay total Google guardado.', 'Pulsar Calcular total Google para esta comunidad.')
    elsif state.google_total_count.to_i.zero?
      add_issue(issues, :warning, region, category, 'Google devolvio total 0.', 'Validar si la categoria/tipo de Google tiene sentido para esta comunidad.')
    end

    if state.google_total_known? && state.google_total_counted_at.blank?
      add_issue(issues, :warning, region, category, 'Hay total Google, pero falta fecha de conteo.', 'Recalcular para dejar trazabilidad completa.')
    end

    if state.google_total_known? && state.approved_count.to_i > state.google_total_count.to_i
      add_issue(issues, :critical, region, category, 'Los importados superan al total Google calculado.', 'Revisar duplicados, categoria asignada o total Google.')
    end

    if state.google_total_known? && state.google_total_counted_at.present? && state.google_total_counted_at < STALE_AFTER.ago
      add_issue(issues, :info, region, category, "El total Google tiene mas de #{STALE_AFTER.inspect} sin recalcular.", 'Recalcular si necesitas porcentajes frescos.')
    end

    {
      category: category,
      label: label,
      google_total_known: state.google_total_known?,
      google_total_count: state.google_total_count,
      google_total_counted_at: state.google_total_counted_at,
      google_error: state.google_total_count_error,
      approved_count: state.approved_count.to_i,
      pending_count: state.pending_count.to_i,
      duplicate_count: state.duplicate_count.to_i,
      rejected_count: state.rejected_count.to_i,
      total_candidates: state.total_candidates.to_i,
      actual_counts: actual_counts,
      percentage: state.google_import_percentage
    }
  end

  def audit_region_shape(region, issues)
    strategy = region.has_attribute?(:google_count_location_strategy) ? region.google_count_location_strategy : 'region'
    unless %w[region circle].include?(strategy.to_s)
      add_issue(issues, :critical, region, nil, "Estrategia de geometria desconocida: #{strategy.inspect}.", 'Debe ser region o circle.')
    end

    if strategy == 'region' && region.google_region_resource_name.blank?
      add_issue(issues, :warning, region, nil, 'La comunidad usa estrategia region pero no tiene Google Region Place ID guardado.', 'Se resolvera automaticamente al recalcular, pero conviene revisar si ya habias calculado esta comunidad.')
    end

    if strategy == 'circle'
      add_issue(issues, :info, region, nil, 'La comunidad usa circulo aproximado por fallback.', 'Los totales pueden incluir locales cercanos fuera del limite administrativo exacto.')
    end
  end

  def audit_excluded_categories(region, states_by_category, issues)
    excluded_categories = states_by_category.keys - categories
    excluded_categories.each do |category|
      state = states_by_category[category]
      next unless state&.google_total_known? || state&.google_total_count_error.present?

      add_issue(
        issues,
        :info,
        region,
        category,
        'Esta categoria tiene datos Google guardados pero ya no forma parte del importador.',
        'Se ignora en porcentajes actuales. No hace falta tocarlo salvo que quieras limpiar historico.'
      )
    end
  end

  def audit_category_distribution(region, category_summaries, issues)
    known_summaries = category_summaries.select { |summary| summary[:google_total_known] }
    google_total = known_summaries.sum { |summary| summary[:google_total_count].to_i }
    return if google_total.zero?

    known_summaries.each do |summary|
      count = summary[:google_total_count].to_i
      share = count.to_f / google_total
      next unless count >= 1_000 && share >= 0.70

      add_issue(
        issues,
        :warning,
        region,
        summary[:category],
        "La categoria concentra #{(share * 100).round}% del total Google regional.",
        'Validar si los tipos de Google usados son demasiado amplios para esta categoria.'
      )
    end

    restaurant = category_summaries.find { |summary| summary[:category] == 'restaurante' }
    hotel = category_summaries.find { |summary| summary[:category] == 'hotel' }
    return unless restaurant&.dig(:google_total_known) && hotel&.dig(:google_total_known)

    restaurant_count = restaurant[:google_total_count].to_i
    hotel_count = hotel[:google_total_count].to_i
    return unless restaurant_count.positive? && hotel_count >= 10_000 && hotel_count > restaurant_count * 3

    add_issue(
      issues,
      :warning,
      region,
      'hotel',
      "Hoteles tiene #{hotel_count} resultados frente a #{restaurant_count} restaurantes.",
      'Este ratio suele indicar que lodging/hotel esta capturando lugares demasiado amplios. Conviene validar con auditoria live y, si aplica, ajustar tipos de Google.'
    )
  end

  def audit_live_google(summaries, issues)
    base_report = {
      enabled: @live_google,
      scope: @live_scope,
      limit: @live_limit,
      api_key_present: GooglePlacesAggregateClient.api_key.present?,
      selected_cells: 0,
      checked_cells: 0,
      skipped_by_limit: 0,
      estimated_google_requests: 0,
      executed_google_requests: 0,
      differences: 0,
      errors: 0,
      results: [],
      skipped: []
    }
    return base_report unless @live_google

    unless base_report[:api_key_present]
      add_issue(
        issues,
        :critical,
        nil,
        nil,
        'La auditoria live no se pudo ejecutar porque falta GOOGLE_PLACES_API_KEY o GOOGLE_MAPS_API_KEY.',
        'Configura la API key en el servidor y vuelve a lanzar Auditar con Google.'
      )
      base_report[:errors] = 1
      return base_report
    end

    client = GooglePlacesAggregateClient.new
    candidates = live_check_candidates(summaries)
    selected = candidates.first(@live_limit)
    skipped = candidates.drop(@live_limit)
    base_report[:selected_cells] = candidates.size
    base_report[:skipped_by_limit] = skipped.size
    base_report[:skipped] = skipped.first(30).map { |cell| live_cell_payload(cell) }

    selected.each do |cell|
      base_report[:estimated_google_requests] += estimated_live_requests_for(client, cell.fetch(:region))
      result = live_google_check(client, cell)
      base_report[:executed_google_requests] += result[:google_requests].to_i
      base_report[:checked_cells] += 1
      base_report[:errors] += 1 if result[:status] == 'error'
      base_report[:differences] += 1 if result[:status] == 'different'
      base_report[:results] << result.except(:google_requests)
      add_live_issue(result, issues)
    end

    base_report
  end

  def live_check_candidates(summaries)
    cells = summaries.flat_map do |summary|
      region = regions.find { |candidate| candidate.id == summary.dig(:region, :id) }
      states_by_category = region.region_categories.index_by(&:category)

      summary.fetch(:categories).map do |category_summary|
        {
          region: region,
          category: category_summary.fetch(:category),
          label: category_summary.fetch(:label),
          state: states_by_category[category_summary.fetch(:category)],
          summary: category_summary,
          region_summary: summary
        }
      end
    end

    case @live_scope
    when 'all'
      cells
    when 'issues'
      cells.select { |cell| live_priority_score(cell).positive? }
    else
      cells.sort_by { |cell| [-live_priority_score(cell), -cell.dig(:summary, :google_total_count).to_i, cell.fetch(:region).position.to_i, categories.index(cell.fetch(:category)).to_i] }
    end
  end

  def live_priority_score(cell)
    state = cell[:state]
    summary = cell[:summary]
    score = 0
    score += 100 if state.blank?
    score += 90 if summary[:google_error].present?
    score += 80 unless summary[:google_total_known]
    score += 60 if summary[:google_total_known] && summary[:google_total_count].to_i.zero?
    score += 50 if suspicious_live_distribution_cell?(cell)
    score += 40 if summary[:google_total_counted_at].present? && summary[:google_total_counted_at] < STALE_AFTER.ago
    score += 30 if summary[:actual_counts].present? && summary[:actual_counts] != stored_counts_from_summary(summary)
    score
  end

  def suspicious_live_distribution_cell?(cell)
    summary = cell.fetch(:summary)
    return false unless summary[:google_total_known]

    count = summary[:google_total_count].to_i
    region_total = cell.dig(:region_summary, :google_total_count).to_i
    return true if count >= 1_000 && region_total.positive? && (count.to_f / region_total) >= 0.70

    return false unless summary[:category] == 'hotel'

    restaurant = Array(cell.dig(:region_summary, :categories)).find { |category_summary| category_summary[:category] == 'restaurante' }
    restaurant_count = restaurant&.dig(:google_total_count).to_i
    restaurant_count.positive? && count >= 10_000 && count > restaurant_count * 3
  end

  def stored_counts_from_summary(summary)
    {
      total_candidates: summary[:total_candidates].to_i,
      pending_count: summary[:pending_count].to_i,
      approved_count: summary[:approved_count].to_i,
      rejected_count: summary[:rejected_count].to_i,
      duplicate_count: summary[:duplicate_count].to_i
    }
  end

  def estimated_live_requests_for(client, region)
    return 1 if client.circle_fallback_enabled?(region)
    return 1 if @region_place_cache.key?(region.id)
    return 1 if region.google_region_resource_name.present?

    2
  end

  def live_google_check(client, cell)
    region = cell.fetch(:region)
    category = cell.fetch(:category)
    state = cell.fetch(:state)
    google_requests = 0
    switched_to_circle = false

    begin
      region_lookup_request = live_region_place_lookup_required?(client, region)
      google_requests += 1 if region_lookup_request
      region_place, resolved_requests = live_region_place_for(client, region)
      google_requests += resolved_requests unless region_lookup_request
      google_requests += 1
      live_count = client.count_region_category(region: region, region_place: region_place, category: category)
    rescue GooglePlacesAggregateClient::RequestError => e
      if client.unsupported_region_geometry_error?(e) && client.circle_fallback_available?(region) && !client.circle_fallback_enabled?(region)
        client.enable_circle_fallback!(region, e)
        region.reload
        @region_place_cache.delete(region.id)
        switched_to_circle = true
        google_requests += 1
        begin
          live_count = client.count_region_category(region: region, region_place: nil, category: category)
        rescue GooglePlacesAggregateClient::RequestError => fallback_error
          return live_error_result(cell, fallback_error, google_requests)
        end
      else
        return live_error_result(cell, e, google_requests)
      end
    end

    stored_count = state&.google_total_known? ? state.google_total_count.to_i : nil
    difference = stored_count.nil? ? nil : live_count - stored_count
    difference_percentage = live_difference_percentage(stored_count, live_count)
    status =
      if stored_count.nil?
        'missing_stored'
      elsif difference.to_i.zero?
        'same'
      else
        'different'
      end

    {
      region: live_region_payload(region),
      category: category,
      label: cell.fetch(:label),
      status: status,
      stored_count: stored_count,
      live_count: live_count,
      difference: difference,
      difference_percentage: difference_percentage,
      significant_difference: significant_live_difference?(stored_count, live_count),
      switched_to_circle: switched_to_circle,
      google_requests: google_requests
    }
  rescue GooglePlacesAggregateClient::MissingApiKeyError => e
    live_error_result(cell, e, google_requests)
  end

  def live_region_place_lookup_required?(client, region)
    !client.circle_fallback_enabled?(region) &&
      !@region_place_cache.key?(region.id) &&
      region.google_region_resource_name.blank?
  end

  def live_region_place_for(client, region)
    return [nil, 0] if client.circle_fallback_enabled?(region)

    cached = @region_place_cache[region.id]
    return cached if cached.present?

    region_place, resolved_region_place = client.region_place_resource_name(region)
    result = [region_place, resolved_region_place ? 1 : 0]
    @region_place_cache[region.id] = result
    result
  end

  def live_error_result(cell, error, google_requests)
    {
      region: live_region_payload(cell.fetch(:region)),
      category: cell.fetch(:category),
      label: cell.fetch(:label),
      status: 'error',
      stored_count: cell.dig(:summary, :google_total_count),
      live_count: nil,
      difference: nil,
      difference_percentage: nil,
      significant_difference: false,
      switched_to_circle: false,
      error_message: error.message.to_s.squish,
      error_details: error.respond_to?(:details) ? error.details.to_s.truncate(MAX_LIVE_ERROR_DETAILS_LENGTH) : error.message.to_s,
      google_requests: google_requests
    }
  end

  def add_live_issue(result, issues)
    region_payload = result[:region]
    region = regions.find { |candidate| candidate.id == region_payload[:id] }
    category = result[:category]

    case result[:status]
    when 'error'
      add_issue(issues, :critical, region, category, "Auditoria live Google fallo: #{result[:error_message]}", 'Revisa el detalle tecnico del bloque live antes de confiar en este total.')
    when 'missing_stored'
      add_issue(issues, :warning, region, category, "Google live devolvio #{result[:live_count]}, pero no hay total guardado.", 'Recalcula/guarda el total Google de esta comunidad para que el progreso use este denominador.')
    when 'different'
      severity = result[:significant_difference] ? :warning : :info
      add_issue(
        issues,
        severity,
        region,
        category,
        "Google live difiere del total guardado: guardado #{result[:stored_count]}, live #{result[:live_count]} (delta #{result[:difference]}).",
        'Si la diferencia importa para el avance, recalcula el total Google de esta comunidad/categoria.'
      )
    end

    return unless result[:switched_to_circle]

    add_issue(
      issues,
      :info,
      region,
      category,
      'Durante la auditoria live se activo fallback de circulo para esta comunidad.',
      'Google no soportaba la geometria regional exacta; los proximos conteos usaran aproximacion circular.'
    )
  end

  def live_difference_percentage(stored_count, live_count)
    return if stored_count.nil?

    denominator = [stored_count.to_i.abs, live_count.to_i.abs].max
    return 0 if denominator.zero?

    (((live_count.to_i - stored_count.to_i).abs.to_f / denominator) * 100).round(2)
  end

  def significant_live_difference?(stored_count, live_count)
    return false if stored_count.nil?

    difference = (live_count.to_i - stored_count.to_i).abs
    percentage = live_difference_percentage(stored_count, live_count).to_f
    difference >= 25 && percentage >= 5
  end

  def live_cell_payload(cell)
    {
      region: live_region_payload(cell.fetch(:region)),
      category: cell.fetch(:category),
      label: cell.fetch(:label),
      stored_count: cell.dig(:summary, :google_total_count)
    }
  end

  def live_region_payload(region)
    {
      id: region.id,
      name: region.name,
      slug: region.slug
    }
  end

  def build_totals(summaries, issues)
    {
      regions: summaries.size,
      categories_per_region: categories.size,
      expected_cells: summaries.size * categories.size,
      counted_cells: summaries.sum { |summary| summary[:counted_categories] },
      google_total_count: summaries.sum { |summary| summary[:google_total_count].to_i },
      approved_count: summaries.sum { |summary| summary[:approved_count].to_i },
      missing_vs_google: summaries.sum { |summary| summary[:missing_vs_google].to_i },
      percentage: percentage_for(
        summaries.sum { |summary| summary[:approved_count].to_i },
        summaries.sum { |summary| summary[:google_total_count].to_i }
      ),
      critical_issues: issues.count { |issue| issue[:severity] == :critical },
      warning_issues: issues.count { |issue| issue[:severity] == :warning },
      info_issues: issues.count { |issue| issue[:severity] == :info }
    }
  end

  def recommendations_for(issues)
    recommendations = []
    recommendations << 'Recalcula comunidades/categorias con errores criticos antes de confiar en porcentajes globales.' if issues.any? { |issue| issue[:severity] == :critical }
    recommendations << 'Sincroniza contadores internos donde haya diferencia entre candidatos reales y contadores guardados.' if issues.any? { |issue| issue[:message].include?('contadores internos') }
    recommendations << 'Los conteos con fallback de circulo son aproximados; usalos como estimacion operativa, no como frontera administrativa exacta.' if issues.any? { |issue| issue[:message].include?('circulo aproximado') }
    recommendations << 'Revisa categorias que concentran demasiado volumen regional; pueden tener tipos Google demasiado amplios.' if issues.any? { |issue| issue[:message].include?('concentra') || issue[:message].include?('frente a') }
    recommendations << 'La auditoria live con Google detecto diferencias; recalcula esas comunidades si quieres refrescar porcentajes.' if issues.any? { |issue| issue[:message].include?('Google live difiere') }
    recommendations << 'El precalculo parece consistente con los datos locales disponibles.' if recommendations.empty?
    recommendations
  end

  def actual_candidate_counts(state)
    counts = state.import_candidates.group(:status).count
    {
      total_candidates: counts.values.sum,
      pending_count: counts['pending'].to_i,
      approved_count: counts['approved'].to_i,
      rejected_count: counts['rejected'].to_i,
      duplicate_count: counts['duplicate'].to_i
    }
  end

  def stored_candidate_counts(state)
    {
      total_candidates: state.total_candidates.to_i,
      pending_count: state.pending_count.to_i,
      approved_count: state.approved_count.to_i,
      rejected_count: state.rejected_count.to_i,
      duplicate_count: state.duplicate_count.to_i
    }
  end

  def empty_category_summary(category, label)
    {
      category: category,
      label: label,
      google_total_known: false,
      google_total_count: nil,
      google_total_counted_at: nil,
      google_error: nil,
      approved_count: 0,
      pending_count: 0,
      duplicate_count: 0,
      rejected_count: 0,
      total_candidates: 0,
      actual_counts: {},
      percentage: nil
    }
  end

  def region_payload(region)
    {
      id: region.id,
      name: region.name,
      slug: region.slug,
      country_code: region.country_code,
      status: region.status,
      google_region_place_id: region.has_attribute?(:google_region_place_id) ? region.google_region_place_id : nil,
      google_count_location_strategy: region.has_attribute?(:google_count_location_strategy) ? region.google_count_location_strategy : 'region',
      google_count_location_note: region.has_attribute?(:google_count_location_note) ? region.google_count_location_note : nil
    }
  end

  def add_issue(issues, severity, region, category, message, suggestion)
    issues << {
      severity: severity,
      region: region&.name,
      region_slug: region&.slug,
      category: category,
      category_label: category.present? ? label_for(category) : nil,
      message: message,
      suggestion: suggestion
    }
  end

  def label_for(category)
    GooglePlacesBlackCoffeeClient.config_for(category)[:label]
  rescue KeyError
    category.to_s.humanize
  end

  def percentage_for(value, total)
    return 0 if total.to_i.zero?

    ((value.to_f / total.to_i) * 100).round
  end
end
