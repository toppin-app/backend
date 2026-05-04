class BlackCoffeeImportPhotoRefreshRunner
  DEFAULT_STEP_BUDGET = 6
  DEFAULT_TIME_BUDGET_SECONDS = 6
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

  def self.start!(import_run:, candidate_ids:)
    active_batch = import_run.photo_refresh_batches.active.recent_first.first
    return active_batch if active_batch.present?

    candidates = import_run.import_candidates.where(id: Array(candidate_ids).map(&:to_i)).to_a
    eligible_candidates = candidates.select do |candidate|
      candidate.missing_images? && candidate.image_refreshable?
    end
    ids = eligible_candidates
          .sort_by { |candidate| [candidate.google_photo_reference_list.any? ? 0 : 1, candidate.id] }
          .map(&:id)
          .uniq
    raise 'Selecciona al menos un candidato valido con imagen pendiente y datos reutilizables de Google.' if ids.empty?

    batch = import_run.photo_refresh_batches.create!(
      status: 'pending',
      candidate_ids_payload: ids,
      pending_candidate_ids_payload: ids
    )
    batch.refresh_counts!
    batch
  end

  def self.advance!(batch:, step_budget: DEFAULT_STEP_BUDGET, time_budget_seconds: DEFAULT_TIME_BUDGET_SECONDS)
    new(batch).advance!(step_budget: step_budget, time_budget_seconds: time_budget_seconds)
  end

  def self.retry_failed!(batch:)
    new(batch).retry_failed!
  end

  def initialize(batch, client: GooglePlacesBlackCoffeeClient.new)
    @batch = batch
    @client = client
  end

  def advance!(step_budget:, time_budget_seconds:)
    return @batch if @batch.finished?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    fatal_error = nil
    processed_candidates = 0

    loop do
      break if processed_candidates >= step_budget
      break if processed_candidates.positive? && elapsed_seconds(started_at) >= time_budget_seconds

      candidate = claim_next_candidate
      break if candidate.blank?

      result = process_candidate(candidate)
      processed_candidates += 1
      fatal_error = result[:fatal_error] if result[:fatal_error].present?
      break if fatal_error.present?
    end

    @batch.reload
    if fatal_error.present?
      @batch
    elsif @batch.pending_candidate_ids.empty?
      finalize_completed_batch!
    else
      @batch.refresh_counts!
    end

    @batch.reload
  end

  def retry_failed!
    raise 'No hay reintento pendiente para este lote.' unless @batch.retryable?

    BlackCoffeeImportPhotoRefreshBatch.transaction do
      @batch.lock!
      retry_ids = (@batch.pending_candidate_ids + @batch.failed_candidate_ids).uniq
      @batch.update!(
        status: 'pending',
        pending_candidate_ids_payload: retry_ids,
        failed_candidate_ids_payload: [],
        error_message: nil,
        current_candidate_id: nil,
        current_candidate_name: nil,
        finished_at: nil,
        last_advanced_at: nil
      )
      @batch.refresh_counts!
    end

    @batch.reload
  end

  private

  def claim_next_candidate
    BlackCoffeeImportPhotoRefreshBatch.transaction do
      @batch.lock!
      return nil unless @batch.active?

      pending_ids = @batch.pending_candidate_ids
      return nil if pending_ids.empty?

      candidate_id = pending_ids.shift
      candidate = @batch.black_coffee_import_run.import_candidates.find_by(id: candidate_id)
      @batch.update!(
        status: 'running',
        pending_candidate_ids_payload: pending_ids,
        started_at: @batch.started_at || Time.current,
        last_advanced_at: Time.current,
        current_candidate_id: candidate_id,
        current_candidate_name: candidate&.name
      )
      candidate || CandidatePlaceholder.new(candidate_id)
    end
  end

  def process_candidate(candidate)
    requests_count = 0

    unless candidate.respond_to?(:image_url_list)
      mark_candidate_skipped!(candidate_id: candidate.id, candidate_name: nil, requests_count: requests_count)
      return {}
    end

    if candidate.image_url_list.any?
      mark_candidate_skipped!(candidate_id: candidate.id, candidate_name: candidate.name, requests_count: requests_count)
      return {}
    end

    result = fetch_candidate_images(candidate)
    requests_count += result[:requests_count].to_i

    if result[:image_urls].any?
      candidate.update!(
        image_urls: result[:image_urls],
        google_photo_references: result[:google_photo_references].presence || candidate.google_photo_references,
        author_attributions: result[:author_attributions].presence || candidate.author_attributions,
        raw_payload: merged_raw_payload(candidate.raw_payload, result[:raw_photos])
      )
      mark_candidate_refreshed!(candidate_id: candidate.id, candidate_name: candidate.name, requests_count: requests_count)
    else
      mark_candidate_skipped!(candidate_id: candidate.id, candidate_name: candidate.name, requests_count: requests_count)
    end

    {}
  rescue GooglePlacesBlackCoffeeClient::MissingApiKeyError, GooglePlacesBlackCoffeeClient::RequestError => e
    if fatal_google_error?(e.message)
      requeue_candidate_and_fail_batch!(
        candidate_id: candidate.id,
        candidate_name: candidate.respond_to?(:name) ? candidate.name : nil,
        message: e.message,
        requests_count: requests_count
      )
      return { fatal_error: e.message }
    end

    mark_candidate_failed!(
      candidate_id: candidate.id,
      candidate_name: candidate.respond_to?(:name) ? candidate.name : nil,
      message: e.message,
      requests_count: requests_count
    )
    {}
  rescue StandardError => e
    mark_candidate_failed!(
      candidate_id: candidate.id,
      candidate_name: candidate.respond_to?(:name) ? candidate.name : nil,
      message: "No se pudieron refrescar las imagenes: #{e.message}",
      requests_count: requests_count
    )
    {}
  end

  def fetch_candidate_images(candidate)
    if candidate.google_photo_reference_list.any?
      begin
        result = @client.photo_urls_from_references(candidate.google_photo_reference_list)
        return result.merge(
          google_photo_references: candidate.google_photo_reference_list,
          author_attributions: Array(candidate.author_attributions),
          raw_photos: Array(candidate.raw_payload.is_a?(Hash) ? candidate.raw_payload['photos'] : nil)
        )
      rescue GooglePlacesBlackCoffeeClient::RequestError => e
        raise if fatal_google_error?(e.message) || candidate.google_place_id.blank?
      end
    end

    return empty_image_result if candidate.google_place_id.blank?

    @client.fetch_place_photo_bundle(place_id: candidate.google_place_id)
  end

  def merged_raw_payload(raw_payload, raw_photos)
    payload =
      if raw_payload.is_a?(Hash)
        raw_payload.deep_dup
      elsif raw_payload.respond_to?(:to_h)
        raw_payload.to_h
      else
        {}
      end
    payload['photos'] = raw_photos if raw_photos.present?
    payload
  end

  def mark_candidate_refreshed!(candidate_id:, candidate_name:, requests_count:)
    update_batch_lists!(
      candidate_id: candidate_id,
      candidate_name: candidate_name,
      requests_count: requests_count,
      target: :refreshed
    )
  end

  def mark_candidate_skipped!(candidate_id:, candidate_name:, requests_count:)
    update_batch_lists!(
      candidate_id: candidate_id,
      candidate_name: candidate_name,
      requests_count: requests_count,
      target: :skipped
    )
  end

  def mark_candidate_failed!(candidate_id:, candidate_name:, message:, requests_count:)
    update_batch_lists!(
      candidate_id: candidate_id,
      candidate_name: candidate_name,
      requests_count: requests_count,
      target: :failed
    )
  end

  def update_batch_lists!(candidate_id:, candidate_name:, requests_count:, target:, error_message: nil)
    BlackCoffeeImportPhotoRefreshBatch.transaction do
      @batch.lock!
      refreshed_ids = @batch.refreshed_candidate_ids
      skipped_ids = @batch.skipped_candidate_ids
      failed_ids = @batch.failed_candidate_ids

      case target
      when :refreshed
        refreshed_ids << candidate_id
      when :skipped
        skipped_ids << candidate_id
      when :failed
        failed_ids << candidate_id
      end

      @batch.update!(
        refreshed_candidate_ids_payload: refreshed_ids.uniq,
        skipped_candidate_ids_payload: skipped_ids.uniq,
        failed_candidate_ids_payload: failed_ids.uniq,
        requests_count: @batch.requests_count.to_i + requests_count.to_i,
        current_candidate_id: nil,
        current_candidate_name: nil,
        error_message: error_message.present? ? error_message.to_s.truncate(1_000) : @batch.error_message
      )
      @batch.refresh_counts!
    end
  end

  def requeue_candidate_and_fail_batch!(candidate_id:, candidate_name:, message:, requests_count:)
    BlackCoffeeImportPhotoRefreshBatch.transaction do
      @batch.lock!
      pending_ids = @batch.pending_candidate_ids
      pending_ids.unshift(candidate_id) unless pending_ids.include?(candidate_id)
      @batch.update!(
        status: 'failed',
        pending_candidate_ids_payload: pending_ids,
        requests_count: @batch.requests_count.to_i + requests_count.to_i,
        current_candidate_id: nil,
        current_candidate_name: nil,
        error_message: message.to_s.truncate(1_000),
        finished_at: Time.current
      )
      @batch.refresh_counts!
    end
  end

  def finalize_completed_batch!
    BlackCoffeeImportPhotoRefreshBatch.transaction do
      @batch.lock!
      @batch.update!(
        status: 'completed',
        current_candidate_id: nil,
        current_candidate_name: nil,
        finished_at: Time.current
      )
      @batch.refresh_counts!
    end
    @batch
  end

  def fatal_google_error?(message)
    FATAL_ERROR_PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
  end

  def empty_image_result
    {
      google_photo_references: [],
      image_urls: [],
      author_attributions: [],
      raw_photos: [],
      requests_count: 0
    }
  end

  def elapsed_seconds(started_at)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end

  CandidatePlaceholder = Struct.new(:id)
end
