class BlackCoffeeVenueGoogleSyncRunner
  DEFAULT_STEP_BUDGET = 6
  DEFAULT_TIME_BUDGET_SECONDS = 6
  MAX_CLAIM_WINDOW = 3
  MAX_ERROR_MESSAGE_LENGTH = 1_000

  def self.start_selected!(venue_ids:)
    active_batch = BlackCoffeeVenueGoogleSyncBatch.active.recent_first.first
    return active_batch if active_batch.present?

    ids = Venue.google_connected.where(id: Array(venue_ids).map(&:to_s)).order(:id).pluck(:id).uniq
    raise 'Selecciona al menos un local conectado a Google.' if ids.empty?

    BlackCoffeeVenueGoogleSyncBatch.create!(
      status: 'pending',
      selection_mode: 'selected_ids',
      venue_ids_payload: ids,
      pending_venue_ids_payload: ids,
      total_venues_count: ids.size,
      pending_venues_count: ids.size
    )
  end

  def self.start_connected_scope!
    active_batch = BlackCoffeeVenueGoogleSyncBatch.active.recent_first.first
    return active_batch if active_batch.present?

    total_connected = Venue.google_connected.count
    raise 'No hay locales conectados a Google para sincronizar.' if total_connected.zero?

    BlackCoffeeVenueGoogleSyncBatch.create!(
      status: 'pending',
      selection_mode: 'connected_scope',
      total_venues_count: total_connected,
      pending_venues_count: total_connected
    )
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

    started_at = monotonic_time
    processed_in_advance = 0

    loop do
      break if processed_in_advance >= step_budget
      break if processed_in_advance.positive? && elapsed_seconds(started_at) >= time_budget_seconds

      claim_limit = [step_budget - processed_in_advance, MAX_CLAIM_WINDOW].min
      claimed_ids = claim_venue_ids(limit: claim_limit)
      break if claimed_ids.empty?

      chunk_result = process_claimed_venues(
        claimed_ids: claimed_ids,
        started_at: started_at,
        time_budget_seconds: time_budget_seconds
      )
      processed_in_advance += chunk_result[:processed_count]
      persist_chunk_result!(chunk_result)
    end

    finalize_if_finished!
    @batch.reload
  end

  def retry_failed!
    failed_ids = @batch.failed_venue_ids
    raise 'No hay sincronizaciones fallidas para reintentar.' if failed_ids.empty?

    BlackCoffeeVenueGoogleSyncBatch.transaction do
      @batch.lock!
      retry_ids = Venue.google_connected.where(id: failed_ids).order(:id).pluck(:id)
      raise 'Los locales fallidos ya no estan conectados a Google y no se pueden reintentar.' if retry_ids.empty?

      @batch.update!(
        status: 'pending',
        selection_mode: 'selected_ids',
        venue_ids_payload: retry_ids,
        pending_venue_ids_payload: retry_ids,
        failed_venue_ids_payload: [],
        total_venues_count: retry_ids.size,
        pending_venues_count: retry_ids.size,
        processed_venues_count: 0,
        synced_venues_count: 0,
        skipped_venues_count: 0,
        failed_venues_count: 0,
        requests_count: 0,
        last_processed_venue_id: nil,
        current_venue_id: nil,
        current_venue_name: nil,
        started_at: nil,
        last_advanced_at: nil,
        finished_at: nil,
        error_message: nil
      )
    end

    @batch.reload
  end

  private

  def claim_venue_ids(limit:)
    BlackCoffeeVenueGoogleSyncBatch.transaction do
      @batch.lock!
      return [] unless @batch.active?

      claimed_ids =
        if @batch.selected_ids?
          claim_selected_ids(limit)
        else
          claim_connected_scope_ids(limit)
        end

      if claimed_ids.any?
        first_id = claimed_ids.first
        @batch.update!(
          status: 'running',
          started_at: @batch.started_at || Time.current,
          last_advanced_at: Time.current,
          current_venue_id: first_id,
          current_venue_name: venue_name_for(first_id)
        )
      end

      claimed_ids
    end
  end

  def claim_selected_ids(limit)
    pending_ids = @batch.pending_venue_ids
    claimed_ids = pending_ids.shift(limit)
    @batch.update!(pending_venue_ids_payload: pending_ids)
    claimed_ids
  end

  def claim_connected_scope_ids(limit)
    queued_ids = @batch.pending_venue_ids
    if queued_ids.any?
      claimed_ids = queued_ids.shift(limit)
      @batch.update!(pending_venue_ids_payload: queued_ids)
      return claimed_ids
    end

    scope = Venue.google_connected.order(:id)
    if @batch.last_processed_venue_id.present?
      scope = scope.where('id > ?', @batch.last_processed_venue_id)
    end

    claimed_ids = scope.limit(limit).pluck(:id)
    @batch.update!(last_processed_venue_id: claimed_ids.last) if claimed_ids.any?
    claimed_ids
  end

  def process_claimed_venues(claimed_ids:, started_at:, time_budget_seconds:)
    venues_by_id = Venue.includes(:venue_subcategory, :venue_images, :venue_schedules).where(id: claimed_ids).index_by(&:id)

    result = {
      processed_count: 0,
      synced_count: 0,
      skipped_count: 0,
      failed_count: 0,
      failed_ids: [],
      leftover_ids: [],
      requests_count: 0,
      error_messages: []
    }

    claimed_ids.each_with_index do |venue_id, index|
      if result[:processed_count].positive? && elapsed_seconds(started_at) >= time_budget_seconds
        result[:leftover_ids] = claimed_ids[index..-1]
        break
      end

      venue = venues_by_id[venue_id]
      venue_result = process_venue(venue)
      result[:processed_count] += 1
      result[:requests_count] += venue_result[:requests_count].to_i

      case venue_result[:outcome]
      when :synced
        result[:synced_count] += 1
      when :skipped
        result[:skipped_count] += 1
      when :failed
        result[:failed_count] += 1
        result[:failed_ids] << venue_id
        result[:error_messages] << venue_result[:message] if venue_result[:message].present?
      end
    end

    result
  end

  def process_venue(venue)
    return { outcome: :skipped, requests_count: 0 } if venue.blank?
    return { outcome: :skipped, requests_count: 0 } unless venue.google_connected?

    sync_data = @client.fetch_place_sync_data(
      place_id: venue.google_place_id,
      category: venue.category,
      fallback_city: venue.city,
      fallback_subcategory: venue.subcategory_name
    )
    requests_count = sync_data.delete(:requests_count).to_i
    changed = apply_sync_data!(venue, sync_data)

    {
      outcome: changed ? :synced : :skipped,
      requests_count: requests_count
    }
  rescue GooglePlacesBlackCoffeeClient::MissingApiKeyError, GooglePlacesBlackCoffeeClient::RequestError => e
    { outcome: :failed, requests_count: 0, message: sync_error_message(venue, e.message) }
  rescue ActiveRecord::RecordInvalid => e
    { outcome: :failed, requests_count: 0, message: sync_error_message(venue, e.record.errors.full_messages.to_sentence.presence || e.message) }
  rescue StandardError => e
    { outcome: :failed, requests_count: 0, message: sync_error_message(venue, e.message) }
  end

  def apply_sync_data!(venue, sync_data)
    google_description = sync_data[:google_description].to_s.strip.presence
    schedule_payload = Array(sync_data[:google_schedule_payload]).presence
    image_urls = Array(sync_data[:image_urls]).map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(10)
    author_attributions_by_index = Array(sync_data[:google_photo_references]).map do |reference|
      reference.respond_to?(:[]) ? (reference['author_attributions'] || reference[:author_attributions] || []) : []
    end

    changed = false

    ActiveRecord::Base.transaction do
      assign_google_attributes!(venue, sync_data)

      if google_description.present?
        venue.description = google_description
      elsif legacy_placeholder_description?(venue.description)
        venue.description = nil
      end

      resolved_subcategory = sync_data[:subcategory].to_s.strip.presence
      if resolved_subcategory.present? && resolved_subcategory != venue.subcategory_name
        venue.assign_subcategory_by_name!(resolved_subcategory)
      end

      if venue.changed?
        venue.save!
        changed = true
      end

      if schedule_payload.present? && venue.weekly_schedule != schedule_payload
        venue.sync_schedule!(schedule_payload)
        changed = true
      end

      if image_urls.any?
        changed = venue.sync_google_images!(
          image_urls: image_urls,
          author_attributions_by_index: author_attributions_by_index
        ) || changed
      end
    end

    changed
  end

  def assign_google_attributes!(venue, sync_data)
    venue.name = sync_data[:name].to_s.strip.presence || venue.name
    venue.address = sync_data[:address].to_s.strip.presence || venue.address
    venue.city = sync_data[:city].to_s.strip.presence || venue.city
    venue.latitude = sync_data[:latitude] unless sync_data[:latitude].nil?
    venue.longitude = sync_data[:longitude] unless sync_data[:longitude].nil?
    venue.google_place_id = sync_data[:google_place_id].to_s.strip.presence || venue.google_place_id
    venue.tags = sync_data[:google_type_tags].presence || venue.tags

    assign_optional_string_attribute(venue, :postal_code, sync_data[:postal_code])
    assign_optional_string_attribute(venue, :state, sync_data[:state])
    assign_optional_string_attribute(venue, :country, sync_data[:country])
    assign_optional_string_attribute(venue, :country_code, sync_data[:country_code])
  end

  def assign_optional_string_attribute(venue, attribute_name, next_value)
    return unless venue.has_attribute?(attribute_name)

    normalized = next_value.to_s.strip.presence
    venue.public_send("#{attribute_name}=", normalized) if normalized.present?
  end

  def persist_chunk_result!(chunk_result)
    BlackCoffeeVenueGoogleSyncBatch.transaction do
      @batch.lock!

      pending_ids = (chunk_result[:leftover_ids] + @batch.pending_venue_ids).uniq
      failed_ids = (@batch.failed_venue_ids + chunk_result[:failed_ids]).uniq
      processed_total = @batch.processed_venues_count.to_i + chunk_result[:processed_count].to_i
      synced_total = @batch.synced_venues_count.to_i + chunk_result[:synced_count].to_i
      skipped_total = @batch.skipped_venues_count.to_i + chunk_result[:skipped_count].to_i
      failed_total = @batch.failed_venues_count.to_i + chunk_result[:failed_count].to_i
      requests_total = @batch.requests_count.to_i + chunk_result[:requests_count].to_i

      pending_total =
        if @batch.selected_ids?
          pending_ids.size
        else
          [@batch.total_venues_count.to_i - processed_total, 0].max
        end

      @batch.update!(
        pending_venue_ids_payload: pending_ids,
        failed_venue_ids_payload: failed_ids,
        pending_venues_count: pending_total,
        processed_venues_count: processed_total,
        synced_venues_count: synced_total,
        skipped_venues_count: skipped_total,
        failed_venues_count: failed_total,
        requests_count: requests_total,
        current_venue_id: nil,
        current_venue_name: nil,
        last_advanced_at: Time.current,
        error_message: merged_error_message(chunk_result[:error_messages])
      )
    end
  end

  def finalize_if_finished!
    @batch.reload
    return if @batch.finished?
    return if more_work_pending?

    status = @batch.failed_venue_ids.any? ? 'failed' : 'completed'

    BlackCoffeeVenueGoogleSyncBatch.transaction do
      @batch.lock!
      @batch.update!(
        status: status,
        pending_venues_count: 0,
        processed_venues_count: @batch.total_venues_count.to_i,
        current_venue_id: nil,
        current_venue_name: nil,
        finished_at: Time.current
      )
    end
  end

  def more_work_pending?
    return @batch.pending_venue_ids.any? if @batch.selected_ids?
    return true if @batch.pending_venue_ids.any?

    scope = Venue.google_connected.order(:id)
    scope = scope.where('id > ?', @batch.last_processed_venue_id) if @batch.last_processed_venue_id.present?
    scope.exists?
  end

  def legacy_placeholder_description?(value)
    value.to_s.squish == BlackCoffeeImportCandidate::LEGACY_PLACEHOLDER_DESCRIPTION
  end

  def merged_error_message(messages)
    messages = Array(messages).map(&:to_s).map(&:squish).reject(&:blank?)
    return @batch.error_message if messages.empty?

    summary = messages.first(3).join(' | ')
    remaining = messages.size - 3
    summary += " | #{remaining} errores mas." if remaining.positive?
    summary.truncate(MAX_ERROR_MESSAGE_LENGTH)
  end

  def sync_error_message(venue, message)
    venue_name = venue&.name.presence || "Local #{venue&.id}"
    "#{venue_name}: #{message}".truncate(MAX_ERROR_MESSAGE_LENGTH)
  end

  def venue_name_for(venue_id)
    Venue.where(id: venue_id).pick(:name)
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def elapsed_seconds(started_at)
    monotonic_time - started_at
  end
end
