class BlackCoffeeVenueCleanup
  OPERATION_DELETE = 'delete'.freeze
  OPERATION_REJECT = 'reject'.freeze
  OPERATION_OPTIONS = {
    OPERATION_DELETE => 'Eliminar definitivamente',
    OPERATION_REJECT => 'Marcar como rechazados'
  }.freeze
  SOURCE_OPTIONS = {
    'all' => 'Todos los locales',
    'google' => 'Importados o vinculados a Google',
    'manual' => 'Manuales o sin Google',
    'internal_test' => 'Marcados como uso interno'
  }.freeze
  VISIBILITY_OPTIONS = {
    'all' => 'Todos',
    'visible' => 'Solo visibles',
    'hidden' => 'Solo ocultos'
  }.freeze

  attr_reader :category, :source, :visibility, :google_tag, :google_primary_type, :operation, :review_rejection_reason, :review_rejection_note

  def initialize(params = {})
    @category = normalized_category(params[:category])
    @source = SOURCE_OPTIONS.key?(params[:source].to_s) ? params[:source].to_s : 'all'
    @visibility = VISIBILITY_OPTIONS.key?(params[:visibility].to_s) ? params[:visibility].to_s : 'all'
    @google_tag = BlackCoffeeTaxonomy.normalize_google_tag(params[:google_tag])
    @google_primary_type = BlackCoffeeTaxonomy.normalize_google_tag(params[:google_primary_type])
    @operation = OPERATION_OPTIONS.key?(params[:operation].to_s) ? params[:operation].to_s : OPERATION_DELETE
    @review_rejection_reason = normalized_rejection_reason(params[:review_rejection_reason])
    @review_rejection_note = params[:review_rejection_note].to_s.strip.presence
  end

  def filters
    {
      operation: operation,
      category: category,
      source: source,
      visibility: visibility,
      google_tag: google_tag,
      google_primary_type: google_primary_type,
      review_rejection_reason: review_rejection_reason,
      review_rejection_note: review_rejection_note
    }
  end

  def delete_operation?
    operation == OPERATION_DELETE
  end

  def reject_operation?
    operation == OPERATION_REJECT
  end

  def scope
    relation = Venue.all
    relation = relation.where(category: category) if category.present?
    relation = Venue.filter_by_google_primary_type(relation, google_primary_type)
    relation = Venue.filter_by_google_tag(relation, google_tag)

    relation =
      case source
      when 'google'
        has_venue_column?(:google_place_id) ? relation.where.not(google_place_id: [nil, '']) : relation.none
      when 'manual'
        has_venue_column?(:google_place_id) ? relation.where(google_place_id: [nil, '']) : relation
      when 'internal_test'
        has_venue_column?(:internal_test) ? relation.where(internal_test: true) : relation.none
      else
        relation
      end

    case visibility
    when 'visible'
      has_venue_column?(:visible) ? relation.where(visible: true) : relation
    when 'hidden'
      has_venue_column?(:visible) ? relation.where(visible: false) : relation.none
    else
      relation
    end
  end

  def preview
    relation = scope
    selected_ids = relation.reselect(:id)

    {
      filters: filters,
      venue_count: relation.count,
      category_counts: relation.group(:category).count.sort.to_h,
      google_linked_count: google_linked_count(relation),
      manual_count: manual_count(relation),
      internal_test_count: flag_count(relation, :internal_test, true),
      visible_count: flag_count(relation, :visible, true),
      hidden_count: flag_count(relation, :visible, false),
      review_pending_count: flag_count(relation, :review_status, Venue::REVIEW_STATUS_PENDING),
      review_approved_count: flag_count(relation, :review_status, Venue::REVIEW_STATUS_APPROVED),
      review_rejected_count: flag_count(relation, :review_status, Venue::REVIEW_STATUS_REJECTED),
      linked_approved_candidates_count: linked_approved_candidates(selected_ids).count,
      linked_duplicate_candidates_count: linked_duplicate_candidates(selected_ids).count,
      orphaned_approved_candidates_count: orphaned_approved_candidates.count,
      orphaned_duplicate_candidates_count: orphaned_duplicate_candidates.count,
      sample_venues: relation.order(updated_at: :desc).limit(10).to_a
    }
  end

  def delete!
    deleted_count = 0
    deleted_ids = []
    import_cleanup = {}

    ActiveRecord::Base.transaction do
      deleted_ids = scope.pluck(:id)
      deleted_count = deleted_ids.size

      Venue.where(id: deleted_ids).find_each(&:destroy!)
      import_cleanup = reset_orphaned_import_links!
    end

    {
      deleted_count: deleted_count,
      deleted_ids_count: deleted_ids.size
    }.merge(import_cleanup)
  end

  def reject!(reviewed_by: nil)
    raise 'Esta instalacion no tiene columna review_status en locales.' unless has_venue_column?(:review_status)
    raise 'Selecciona un motivo de rechazo valido.' unless Venue::REJECTION_REASON_CODES.include?(review_rejection_reason)

    affected_count = 0
    affected_ids = []

    ActiveRecord::Base.transaction do
      affected_ids = scope.pluck(:id)
      affected_count = affected_ids.size

      attributes = {
        review_status: Venue::REVIEW_STATUS_REJECTED,
        review_rejection_reason: review_rejection_reason,
        review_rejection_note: review_rejection_note,
        reviewed_at: Time.current,
        updated_at: Time.current
      }
      attributes[:reviewed_by_id] = reviewed_by.id if reviewed_by.present? && has_venue_column?(:reviewed_by_id)
      attributes[:featured] = false if has_venue_column?(:featured)

      Venue.where(id: affected_ids).update_all(attributes)
    end

    {
      rejected_count: affected_count,
      rejected_ids_count: affected_ids.size,
      review_rejection_reason: review_rejection_reason,
      review_rejection_note_present: review_rejection_note.present?
    }
  end

  private

  def normalized_category(value)
    category = value.to_s.strip
    Venue::CATEGORIES.include?(category) ? category : nil
  end

  def normalized_rejection_reason(value)
    reason = value.to_s.strip
    Venue::REJECTION_REASON_CODES.include?(reason) ? reason : Venue::REJECTION_REASON_CODES.first
  end

  def has_venue_column?(column_name)
    Venue.column_names.include?(column_name.to_s)
  end

  def google_linked_count(relation)
    return 0 unless has_venue_column?(:google_place_id)

    relation.where.not(google_place_id: [nil, '']).count
  end

  def manual_count(relation)
    return 0 unless has_venue_column?(:google_place_id)

    relation.where(google_place_id: [nil, '']).count
  end

  def flag_count(relation, column_name, value)
    return 0 unless has_venue_column?(column_name)

    relation.where(column_name => value).count
  end

  def linked_approved_candidates(venue_ids)
    BlackCoffeeImportCandidate.where(status: 'approved', approved_venue_id: venue_ids)
  end

  def linked_duplicate_candidates(venue_ids)
    BlackCoffeeImportCandidate.where(status: 'duplicate', duplicate_venue_id: venue_ids)
  end

  def orphaned_approved_candidates
    BlackCoffeeImportCandidate
      .where(status: 'approved')
      .where("approved_venue_id IS NULL OR approved_venue_id = '' OR approved_venue_id NOT IN (SELECT id FROM venues)")
  end

  def orphaned_duplicate_candidates
    BlackCoffeeImportCandidate
      .where(status: 'duplicate')
      .where("duplicate_venue_id IS NULL OR duplicate_venue_id = '' OR duplicate_venue_id NOT IN (SELECT id FROM venues)")
  end

  def reset_orphaned_import_links!
    approved_ids = orphaned_approved_candidates.pluck(:id)
    duplicate_ids = orphaned_duplicate_candidates.pluck(:id)
    candidate_ids = (approved_ids + duplicate_ids).uniq
    return empty_import_cleanup if candidate_ids.empty?

    candidates = BlackCoffeeImportCandidate.where(id: candidate_ids)
    run_ids = candidates.distinct.pluck(:black_coffee_import_run_id).compact
    region_category_ids = candidates.distinct.pluck(:black_coffee_import_region_category_id).compact
    region_ids = candidates.distinct.pluck(:black_coffee_import_region_id).compact

    candidates.update_all(
      status: 'pending',
      approved_venue_id: nil,
      duplicate_venue_id: nil,
      reviewed_at: nil,
      updated_at: Time.current
    )

    refresh_import_state(run_ids, region_category_ids, region_ids)

    {
      reset_candidate_count: candidate_ids.size,
      reset_approved_candidate_count: approved_ids.size,
      reset_duplicate_candidate_count: duplicate_ids.size,
      refreshed_runs_count: run_ids.size,
      refreshed_region_categories_count: region_category_ids.size,
      refreshed_regions_count: region_ids.size
    }
  end

  def empty_import_cleanup
    {
      reset_candidate_count: 0,
      reset_approved_candidate_count: 0,
      reset_duplicate_candidate_count: 0,
      refreshed_runs_count: 0,
      refreshed_region_categories_count: 0,
      refreshed_regions_count: 0
    }
  end

  def refresh_import_state(run_ids, region_category_ids, region_ids)
    BlackCoffeeImportRun.where(id: run_ids).find_each(&:refresh_counts!)

    refreshed_category_ids = BlackCoffeeImportRun.where(id: run_ids).pluck(:black_coffee_import_region_category_id).compact
    remaining_region_category_ids = region_category_ids - refreshed_category_ids
    BlackCoffeeImportRegionCategory.where(id: remaining_region_category_ids).find_each(&:refresh_counts!)

    BlackCoffeeImportRegion.where(id: region_ids).find_each(&:refresh_status!)
  end
end
