class BlackCoffeeGoogleImportAudit
  STALE_AFTER = 14.days
  SEVERITIES = %i[critical warning info].freeze

  attr_reader :regions, :categories, :category_labels

  def initialize(
    regions: BlackCoffeeImportRegion.includes(:region_categories).ordered.to_a,
    categories: GooglePlacesBlackCoffeeClient.importable_categories
  )
    @regions = regions
    @categories = categories
    @category_labels = GooglePlacesBlackCoffeeClient.category_options.to_h.invert
  end

  def call
    issues = []
    summaries = regions.map { |region| audit_region(region, issues) }
    totals = build_totals(summaries, issues)

    {
      generated_at: Time.current,
      categories: categories,
      category_labels: category_labels,
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
