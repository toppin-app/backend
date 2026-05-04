class BlackCoffeeImportApprovalRunner
  DEFAULT_STEP_BUDGET = 100
  DEFAULT_TIME_BUDGET_SECONDS = 5
  MAX_CLAIM_WINDOW = 25
  MAX_ERROR_MESSAGE_LENGTH = 1_000

  def self.start_selected!(import_run:, candidate_ids:)
    active_batch = import_run.approval_batches.active.recent_first.first
    return active_batch if active_batch.present?

    ids = import_run.import_candidates.where(id: Array(candidate_ids).map(&:to_i), status: 'pending').order(:id).pluck(:id).uniq
    raise 'Selecciona al menos un candidato pendiente valido.' if ids.empty?

    import_run.approval_batches.create!(
      status: 'pending',
      selection_mode: 'selected_ids',
      candidate_ids_payload: ids,
      pending_candidate_ids_payload: ids,
      total_candidates_count: ids.size,
      pending_candidates_count: ids.size
    )
  end

  def self.start_pending_scope!(import_run:)
    active_batch = import_run.approval_batches.active.recent_first.first
    return active_batch if active_batch.present?

    total_pending = import_run.import_candidates.where(status: 'pending').count
    raise 'No hay candidatos pendientes para aprobar en esta corrida.' if total_pending.zero?

    import_run.approval_batches.create!(
      status: 'pending',
      selection_mode: 'pending_scope',
      total_candidates_count: total_pending,
      pending_candidates_count: total_pending,
      last_processed_candidate_id: 0
    )
  end

  def self.start_pending_with_images_scope!(import_run:)
    active_batch = import_run.approval_batches.active.recent_first.first
    return active_batch if active_batch.present?

    total_pending = import_run.import_candidates.where(status: 'pending').where.not('image_urls IS NULL OR JSON_LENGTH(image_urls) = 0').count
    raise 'No hay candidatos pendientes con imagen para aprobar en esta corrida.' if total_pending.zero?

    import_run.approval_batches.create!(
      status: 'pending',
      selection_mode: 'pending_with_images_scope',
      total_candidates_count: total_pending,
      pending_candidates_count: total_pending,
      last_processed_candidate_id: 0
    )
  end

  def self.advance!(batch:, step_budget: DEFAULT_STEP_BUDGET, time_budget_seconds: DEFAULT_TIME_BUDGET_SECONDS)
    new(batch).advance!(step_budget: step_budget, time_budget_seconds: time_budget_seconds)
  end

  def self.retry_failed!(batch:)
    new(batch).retry_failed!
  end

  def initialize(batch)
    @batch = batch
    @import_run = batch.black_coffee_import_run
  end

  def advance!(step_budget:, time_budget_seconds:)
    return @batch if @batch.finished?

    started_at = monotonic_time
    processed_in_advance = 0

    loop do
      break if processed_in_advance >= step_budget
      break if processed_in_advance.positive? && elapsed_seconds(started_at) >= time_budget_seconds

      claim_limit = [step_budget - processed_in_advance, MAX_CLAIM_WINDOW].min
      claimed_ids = claim_candidate_ids(limit: claim_limit)
      break if claimed_ids.empty?

      chunk_result = process_claimed_candidates(
        claimed_ids: claimed_ids,
        started_at: started_at,
        time_budget_seconds: time_budget_seconds
      )
      processed_in_advance += chunk_result[:processed_count]
      persist_chunk_result!(chunk_result)
      apply_run_count_deltas!(chunk_result)
    end

    finalize_if_finished!
    @batch.reload
  end

  def retry_failed!
    failed_ids = @batch.failed_candidate_ids
    raise 'No hay aprobaciones fallidas pendientes de reintento.' if failed_ids.empty?

    BlackCoffeeImportApprovalBatch.transaction do
      @batch.lock!
      retry_ids = @import_run.import_candidates.where(id: failed_ids, status: 'pending').order(:id).pluck(:id)
      raise 'Los candidatos fallidos ya no estan pendientes y no se pueden reintentar.' if retry_ids.empty?

      @batch.update!(
        status: 'pending',
        selection_mode: 'selected_ids',
        candidate_ids_payload: retry_ids,
        pending_candidate_ids_payload: retry_ids,
        failed_candidate_ids_payload: [],
        total_candidates_count: retry_ids.size,
        pending_candidates_count: retry_ids.size,
        processed_candidates_count: 0,
        approved_candidates_count: 0,
        duplicate_candidates_count: 0,
        skipped_candidates_count: 0,
        failed_candidates_count: 0,
        last_processed_candidate_id: 0,
        current_candidate_id: nil,
        current_candidate_name: nil,
        started_at: nil,
        last_advanced_at: nil,
        finished_at: nil,
        error_message: nil
      )
    end

    @batch.reload
  end

  private

  def claim_candidate_ids(limit:)
    BlackCoffeeImportApprovalBatch.transaction do
      @batch.lock!
      return [] unless @batch.active?

      claimed_ids =
        if @batch.selected_ids?
          claim_selected_ids(limit)
        elsif @batch.pending_with_images_scope?
          claim_pending_with_images_scope_ids(limit)
        else
          claim_pending_scope_ids(limit)
        end

      if claimed_ids.any?
        first_id = claimed_ids.first
        @batch.update!(
          status: 'running',
          started_at: @batch.started_at || Time.current,
          last_advanced_at: Time.current,
          current_candidate_id: first_id,
          current_candidate_name: candidate_name_for(first_id)
        )
      end

      claimed_ids
    end
  end

  def claim_selected_ids(limit)
    pending_ids = @batch.pending_candidate_ids
    claimed_ids = pending_ids.shift(limit)
    @batch.update!(pending_candidate_ids_payload: pending_ids)
    claimed_ids
  end

  def claim_pending_scope_ids(limit)
    queued_ids = @batch.pending_candidate_ids
    if queued_ids.any?
      claimed_ids = queued_ids.shift(limit)
      @batch.update!(pending_candidate_ids_payload: queued_ids)
      return claimed_ids
    end

    scope = @import_run.import_candidates.where(status: 'pending')
    if @batch.last_processed_candidate_id.to_i.positive?
      scope = scope.where('id > ?', @batch.last_processed_candidate_id.to_i)
    end

    claimed_ids = scope.order(:id).limit(limit).pluck(:id)
    @batch.update!(last_processed_candidate_id: claimed_ids.last) if claimed_ids.any?
    claimed_ids
  end

  def claim_pending_with_images_scope_ids(limit)
    queued_ids = @batch.pending_candidate_ids
    if queued_ids.any?
      claimed_ids = queued_ids.shift(limit)
      @batch.update!(pending_candidate_ids_payload: queued_ids)
      return claimed_ids
    end

    scope = @import_run.import_candidates.where(status: 'pending').where.not('image_urls IS NULL OR JSON_LENGTH(image_urls) = 0')
    if @batch.last_processed_candidate_id.to_i.positive?
      scope = scope.where('id > ?', @batch.last_processed_candidate_id.to_i)
    end

    claimed_ids = scope.order(:id).limit(limit).pluck(:id)
    @batch.update!(last_processed_candidate_id: claimed_ids.last) if claimed_ids.any?
    claimed_ids
  end

  def process_claimed_candidates(claimed_ids:, started_at:, time_budget_seconds:)
    candidates_by_id = @import_run.import_candidates.where(id: claimed_ids).index_by(&:id)
    preloaded_venues = preload_existing_venues(candidates_by_id.values)

    result = {
      processed_count: 0,
      approved_count: 0,
      duplicate_count: 0,
      skipped_count: 0,
      failed_count: 0,
      failed_ids: [],
      leftover_ids: [],
      last_processed_candidate_id: nil,
      current_candidate_name: nil,
      error_messages: []
    }

    claimed_ids.each_with_index do |candidate_id, index|
      if result[:processed_count].positive? && elapsed_seconds(started_at) >= time_budget_seconds
        result[:leftover_ids] = claimed_ids[index..-1]
        break
      end

      candidate = candidates_by_id[candidate_id]
      candidate_result = process_candidate(candidate, preloaded_venues)

      result[:processed_count] += 1
      result[:last_processed_candidate_id] = candidate_id
      result[:current_candidate_name] = candidate&.name

      case candidate_result[:outcome]
      when :approved
        result[:approved_count] += 1
      when :duplicate
        result[:duplicate_count] += 1
      when :skipped
        result[:skipped_count] += 1
      when :failed
        result[:failed_count] += 1
        result[:failed_ids] << candidate_id
        result[:error_messages] << candidate_result[:message] if candidate_result[:message].present?
      end
    end

    result
  end

  def process_candidate(candidate, preloaded_venues)
    return { outcome: :skipped } if candidate.blank?
    return { outcome: :skipped } unless candidate.pending?

    preloaded_duplicate = preloaded_duplicate_for(candidate, preloaded_venues)

    venue = candidate.approve!(refresh_counts: false, preloaded_duplicate: preloaded_duplicate)
    register_venue_in_cache(preloaded_venues, venue)

    if candidate.duplicate?
      { outcome: :duplicate }
    else
      { outcome: :approved }
    end
  rescue ActiveRecord::RecordInvalid => e
    { outcome: :failed, message: approval_error_message(candidate, e.record.errors.full_messages.to_sentence.presence || e.message) }
  rescue StandardError => e
    { outcome: :failed, message: approval_error_message(candidate, e.message) }
  end

  def persist_chunk_result!(chunk_result)
    BlackCoffeeImportApprovalBatch.transaction do
      @batch.lock!

      pending_ids = if @batch.selected_ids? || @batch.pending_scope?
                      (chunk_result[:leftover_ids] + @batch.pending_candidate_ids).uniq
                    else
                      []
                    end
      failed_ids = (@batch.failed_candidate_ids + chunk_result[:failed_ids]).uniq

      processed_total = @batch.processed_candidates_count.to_i + chunk_result[:processed_count].to_i
      approved_total = @batch.approved_candidates_count.to_i + chunk_result[:approved_count].to_i
      duplicate_total = @batch.duplicate_candidates_count.to_i + chunk_result[:duplicate_count].to_i
      skipped_total = @batch.skipped_candidates_count.to_i + chunk_result[:skipped_count].to_i
      failed_total = @batch.failed_candidates_count.to_i + chunk_result[:failed_count].to_i

      pending_total =
        if @batch.selected_ids?
          pending_ids.size
        else
          [@batch.total_candidates_count.to_i - processed_total, 0].max
        end

      @batch.update!(
        pending_candidate_ids_payload: pending_ids,
        failed_candidate_ids_payload: failed_ids,
        pending_candidates_count: pending_total,
        processed_candidates_count: processed_total,
        approved_candidates_count: approved_total,
        duplicate_candidates_count: duplicate_total,
        skipped_candidates_count: skipped_total,
        failed_candidates_count: failed_total,
        current_candidate_id: nil,
        current_candidate_name: nil,
        last_advanced_at: Time.current,
        error_message: merged_error_message(chunk_result[:error_messages])
      )
    end
  end

  def apply_run_count_deltas!(chunk_result)
    approved_delta = chunk_result[:approved_count].to_i
    duplicate_delta = chunk_result[:duplicate_count].to_i
    return if approved_delta.zero? && duplicate_delta.zero?

    @import_run.apply_review_deltas!(
      approved_delta: approved_delta,
      duplicate_delta: duplicate_delta
    )
  end

  def finalize_if_finished!
    @batch.reload
    return if @batch.finished?
    return if more_work_pending?

    status = @batch.failed_candidate_ids.any? ? 'failed' : 'completed'

    BlackCoffeeImportApprovalBatch.transaction do
      @batch.lock!
      @batch.update!(
        status: status,
        pending_candidates_count: 0,
        processed_candidates_count: @batch.total_candidates_count.to_i,
        current_candidate_id: nil,
        current_candidate_name: nil,
        finished_at: Time.current
      )
    end
  end

  def more_work_pending?
    return @batch.pending_candidate_ids.any? if @batch.selected_ids?
    return true if @batch.pending_candidate_ids.any?

    scope = @import_run.import_candidates.where(status: 'pending')
    scope = scope.where.not('image_urls IS NULL OR JSON_LENGTH(image_urls) = 0') if @batch.pending_with_images_scope?
    if @batch.last_processed_candidate_id.to_i.positive?
      scope = scope.where('id > ?', @batch.last_processed_candidate_id.to_i)
    end
    scope.exists?
  end

  def preload_existing_venues(candidates)
    preload = {
      by_google_place_id: {},
      by_name: {},
      by_name_and_city: {}
    }

    candidates = Array(candidates).compact
    return preload if candidates.empty?

    if Venue.column_names.include?('google_place_id')
      place_ids = candidates.map { |candidate| candidate.google_place_id.to_s.strip.presence }.compact.uniq
      preload[:by_google_place_id] = Venue.where(google_place_id: place_ids).index_by(&:google_place_id) if place_ids.any?
    end

    normalized_names = candidates.map { |candidate| normalize_name(candidate.name) }.compact.uniq
    return preload if normalized_names.empty?

    Venue.where('LOWER(name) IN (?)', normalized_names).find_each do |venue|
      normalized_name = normalize_name(venue.name)
      next if normalized_name.blank?

      preload[:by_name][normalized_name] ||= venue

      normalized_city = normalize_name(venue.city)
      next if normalized_city.blank?

      preload[:by_name_and_city][[normalized_name, normalized_city]] ||= venue
    end

    preload
  end

  def preloaded_duplicate_for(candidate, preloaded_venues)
    if Venue.column_names.include?('google_place_id')
      venue = preloaded_venues[:by_google_place_id][candidate.google_place_id.to_s.presence]
      return venue if venue.present?
    end

    normalized_name = normalize_name(candidate.name)
    return if normalized_name.blank?

    normalized_city = normalize_name(candidate.city)
    if normalized_city.present?
      venue = preloaded_venues[:by_name_and_city][[normalized_name, normalized_city]]
      return venue if venue.present?
    end

    preloaded_venues[:by_name][normalized_name]
  end

  def register_venue_in_cache(preloaded_venues, venue)
    return unless venue.present?

    if Venue.column_names.include?('google_place_id') && venue.google_place_id.present?
      preloaded_venues[:by_google_place_id][venue.google_place_id] = venue
    end

    normalized_name = normalize_name(venue.name)
    return if normalized_name.blank?

    preloaded_venues[:by_name][normalized_name] ||= venue

    normalized_city = normalize_name(venue.city)
    return if normalized_city.blank?

    preloaded_venues[:by_name_and_city][[normalized_name, normalized_city]] ||= venue
  end

  def merged_error_message(messages)
    messages = Array(messages).map(&:to_s).map(&:squish).reject(&:blank?)
    return @batch.error_message if messages.empty?

    summarized = messages.first(3).join(' | ')
    remaining = messages.size - 3
    summarized += " | #{remaining} errores mas." if remaining.positive?
    summarized.truncate(MAX_ERROR_MESSAGE_LENGTH)
  end

  def approval_error_message(candidate, message)
    base_name = candidate&.name.presence || "Candidato ##{candidate&.id}"
    "#{base_name}: #{message}".truncate(MAX_ERROR_MESSAGE_LENGTH)
  end

  def candidate_name_for(candidate_id)
    @import_run.import_candidates.where(id: candidate_id).pick(:name)
  end

  def normalize_name(value)
    value.to_s.strip.downcase.presence
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def elapsed_seconds(started_at)
    monotonic_time - started_at
  end
end
