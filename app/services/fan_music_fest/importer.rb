module FanMusicFest
  class Importer
    MAX_PAGES = 13
    DEFAULT_SOURCE_URL = "#{FanMusicFest::Client::BASE_URL}#{FanMusicFest::Client::CALENDAR_PATH}".freeze

    attr_reader :run, :client, :parser, :normalizer

    def initialize(run:, client: nil, parser: Parser.new, normalizer: Normalizer.new)
      @run = run
      @client = client || Client.new(request_delay_seconds: run.request_delay_seconds)
      @parser = parser
      @normalizer = normalizer
    end

    def self.enqueue!(created_by:, attributes:)
      run = BlackCoffeeFestivalImportRun.create!(
        {
          source: BlackCoffeeFestivalImportRun::SOURCE_FAN_MUSIC_FEST,
          status: 'pending',
          source_url: DEFAULT_SOURCE_URL,
          created_by: created_by
        }.merge(attributes)
      )
      BlackCoffeeFestivalImportJob.perform_later(run.id)
      run
    end

    def perform!
      run.update!(
        status: 'running',
        started_at: run.started_at || Time.current,
        error_message: nil
      )

      run.refresh_details? ? process_existing_festivals : process_calendar

      finish_run!
    rescue StandardError => e
      run.update!(
        status: cancelled? ? 'cancelled' : 'failed',
        error_message: e.message,
        completed_at: Time.current
      )
      raise unless cancelled?
    ensure
      refresh_counts!
    end

    private

    def process_calendar
      each_listing_page do |page_index|
        break if cancelled?

        process_listing_page(page_index)
      end
    end

    def process_existing_festivals
      refresh_scope.limit(run.max_details.to_i).find_each do |venue|
        break if cancelled?

        refresh_existing_venue(venue)
        refresh_counts!
      end
    end

    def refresh_scope
      Venue.where(
        category: 'festival',
        external_source: FanMusicFest::Normalizer::SOURCE
      ).where.not(external_source_url: [nil, '']).order(:id)
    end

    def refresh_existing_venue(venue)
      result = DetailRefresher.new(
        client: client,
        parser: parser,
        normalizer: normalizer
      ).call(
        venue: venue,
        dry_run: run.dry_run?,
        preserve_manual_edits: run.preserve_manual_edits?
      )

      normalized = result.normalized.merge(refresh_changes: result.changes)
      create_item!(
        normalized[:raw_payload] || {},
        normalized,
        status: run.dry_run? ? 'dry_run' : 'updated',
        venue: venue,
        warning_message: result.warnings.to_sentence.presence
      )
    rescue StandardError => e
      create_item!(
        {},
        {
          source_url: venue.safe_fan_music_fest_source_url,
          name: venue.name,
          city: venue.city,
          state: venue.state,
          country: venue.country,
          country_code: venue.country_code
        },
        status: 'failed',
        venue: venue,
        error_message: "#{e.class} - #{e.message}"
      )
    end

    def each_listing_page
      [run.max_pages.to_i, MAX_PAGES].min.times do |page_index|
        yield page_index
      end
    end

    def process_listing_page(page_index)
      html = client.fetch_calendar_page(page: page_index)
      run.update_columns(
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: client.detail_requests_count,
        updated_at: Time.current
      )

      raw_events = parser.parse_listing(html)
      raw_events.each do |raw_event|
        break if cancelled?

        process_raw_event(raw_event)
      end
      refresh_counts!
    end

    def process_raw_event(raw_event)
      normalized = normalizer.normalize(raw_event)
      create_skipped_item!(raw_event, normalized, 'skipped_outside_country', 'El festival no pertenece a Espana.') && return if outside_country?(normalized)
      create_skipped_item!(raw_event, normalized, 'skipped_invalid', 'Faltan datos minimos para crear el local.') && return unless normalized[:valid]

      duplicate = duplicate_venue_for(normalized)
      create_duplicate_item!(raw_event, normalized, duplicate) && return if duplicate.present?

      normalized = enrich_with_detail_if_needed(raw_event, normalized)
      create_skipped_item!(raw_event, normalized, 'skipped_outside_country', 'El detalle confirma que el festival no pertenece a Espana.') && return if outside_country?(normalized)
      create_skipped_item!(raw_event, normalized, 'skipped_invalid', 'El detalle no tiene datos minimos para crear el local.') && return unless normalized[:valid]

      if run.dry_run?
        create_item!(raw_event, normalized, status: 'dry_run')
      else
        create_venue_item!(raw_event, normalized)
      end
    rescue StandardError => e
      create_item!(raw_event, normalized || {}, status: 'failed', error_message: "#{e.class} - #{e.message}")
    end

    def enrich_with_detail_if_needed(raw_event, normalized)
      return normalized unless run.import_details?
      return normalized unless normalized[:source_url].present?
      return normalized if client.detail_requests_count.to_i >= run.max_details.to_i

      detail_html = client.fetch_detail(normalized[:source_url])
      detail_raw = parser.parse_detail(detail_html, source_url: normalized[:source_url])
      run.update_columns(
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: client.detail_requests_count,
        updated_at: Time.current
      )
      normalizer.normalize(raw_event.deep_merge(detail_raw))
    end

    def outside_country?(normalized)
      normalized[:outside_country] || normalized[:country_code] != run.strict_country_code
    end

    def duplicate_venue_for(normalized)
      source_scope = Venue.column_names.include?('external_source') ? Venue.where(external_source: FanMusicFest::Normalizer::SOURCE) : Venue.none
      return source_scope.find_by(external_source_id: normalized[:source_event_id]) if normalized[:source_event_id].present? && Venue.column_names.include?('external_source_id')
      return source_scope.find_by(source_fingerprint: normalized[:fingerprint]) if normalized[:fingerprint].present? && Venue.column_names.include?('source_fingerprint')

      Venue.where(category: 'festival')
           .where('LOWER(name) = ? AND LOWER(city) = ?', normalized[:name].to_s.downcase, normalized[:city].to_s.downcase)
           .first
    end

    def create_duplicate_item!(raw_event, normalized, duplicate)
      create_item!(
        raw_event,
        normalized,
        status: 'skipped_duplicate',
        venue: duplicate,
        error_message: "Ya existe el local #{duplicate.id}."
      )
    end

    def create_skipped_item!(raw_event, normalized, status, message)
      create_item!(raw_event, normalized, status: status, error_message: message)
    end

    def create_venue_item!(raw_event, normalized)
      venue = nil
      ActiveRecord::Base.transaction do
        venue = Venue.create!(venue_attributes(normalized))
        if normalized[:image_url].present?
          venue.venue_images.create!(
            url: normalized[:image_url],
            source: FanMusicFest::Normalizer::SOURCE,
            position: 0
          )
        end
        create_item!(raw_event, normalized, status: 'created', venue: venue)
      end
    end

    def venue_attributes(normalized)
      attrs = {
        name: normalized[:name],
        category: 'festival',
        description: nil,
        address: normalized[:address],
        city: normalized[:city],
        latitude: normalized[:latitude],
        longitude: normalized[:longitude],
        featured: false,
        tags: %w[festival music_festival fanmusicfest]
      }
      attrs[:state] = normalized[:state] if Venue.column_names.include?('state')
      attrs[:country] = normalized[:country].presence || 'Espana' if Venue.column_names.include?('country')
      attrs[:country_code] = 'ES' if Venue.column_names.include?('country_code')
      attrs[:review_status] = run.auto_publish? ? Venue::REVIEW_STATUS_APPROVED : Venue::REVIEW_STATUS_PENDING if Venue.column_names.include?('review_status')
      attrs[:visible] = run.auto_publish? if Venue.column_names.include?('visible')
      attrs[:payment_current] = true if Venue.column_names.include?('payment_current')
      attrs[:internal_test] = false if Venue.column_names.include?('internal_test')
      attrs[:external_source] = FanMusicFest::Normalizer::SOURCE if Venue.column_names.include?('external_source')
      attrs[:external_source_url] = normalized[:source_url] if Venue.column_names.include?('external_source_url')
      attrs[:external_source_id] = normalized[:source_event_id] if Venue.column_names.include?('external_source_id')
      attrs[:source_fingerprint] = normalized[:fingerprint] if Venue.column_names.include?('source_fingerprint')
      attrs[:festival_start_date] = normalized[:start_date] if Venue.column_names.include?('festival_start_date')
      attrs[:festival_end_date] = normalized[:end_date] if Venue.column_names.include?('festival_end_date')
      attrs[:festival_metadata] = festival_metadata(normalized) if Venue.column_names.include?('festival_metadata')
      attrs[:coordinates_source] = normalized[:coordinates_source] if Venue.column_names.include?('coordinates_source')
      attrs[:coordinates_confidence] = normalized[:coordinates_confidence] if Venue.column_names.include?('coordinates_confidence')
      attrs[:source_description] = normalized[:source_description] if Venue.column_names.include?('source_description')
      attrs[:source_description_language] = normalized[:source_description_language] if Venue.column_names.include?('source_description_language')
      attrs[:source_description_status] = normalized[:source_description_status] if Venue.column_names.include?('source_description_status')
      attrs[:official_url] = normalized[:official_url] if Venue.column_names.include?('official_url')
      attrs[:ticket_url] = normalized[:ticket_url] if Venue.column_names.include?('ticket_url')
      attrs[:festival_venue_name] = normalized[:venue_name] if Venue.column_names.include?('festival_venue_name')
      attrs[:festival_raw_location_text] = normalized[:raw_location_text] if Venue.column_names.include?('festival_raw_location_text')
      attrs
    end

    def festival_metadata(normalized)
      {
        edition_title: normalized[:edition_title],
        event_status: normalized[:event_status],
        free: normalized[:free],
        organizer: normalized[:organizer],
        offers: normalized[:offers],
        performers: normalized[:performers],
        ticket_price_text: normalized[:ticket_price_text],
        map_source_url: normalized[:map_source_url],
        source: FanMusicFest::Normalizer::SOURCE
      }
    end

    def create_item!(raw_event, normalized, status:, venue: nil, error_message: nil, warning_message: nil)
      run.items.create!(
        venue: venue,
        status: status,
        source: FanMusicFest::Normalizer::SOURCE,
        source_url: normalized[:source_url],
        source_event_id: normalized[:source_event_id],
        fingerprint: normalized[:fingerprint],
        name: normalized[:name],
        city: normalized[:city],
        state: normalized[:state],
        country: normalized[:country],
        country_code: normalized[:country_code],
        start_date: normalized[:start_date],
        end_date: normalized[:end_date],
        image_url: normalized[:image_url],
        latitude: normalized[:latitude],
        longitude: normalized[:longitude],
        coordinates_source: normalized[:coordinates_source],
        coordinates_confidence: normalized[:coordinates_confidence],
        source_description: normalized[:source_description],
        source_description_language: normalized[:source_description_language],
        source_description_status: normalized[:source_description_status],
        official_url: normalized[:official_url],
        ticket_url: normalized[:ticket_url],
        festival_venue_name: normalized[:venue_name],
        warning_message: warning_message.presence || normalized[:coordinates_warning],
        error_message: error_message,
        raw_payload: raw_event,
        normalized_payload: normalized.except(:raw_payload)
      )
    end

    def cancelled?
      run.reload.cancelled?
    end

    def finish_run!
      run.reload
      return if run.cancelled?

      run.update!(
        status: 'completed',
        completed_at: Time.current
      )
    end

    def refresh_counts!
      run.reload
      counts = run.items.group(:status).count
      request_summary = {
        source: FanMusicFest::Normalizer::SOURCE,
        source_url: run.source_url,
        operation: run.operation,
        requests: {
          robots: client.robots_requests_count,
          listing: client.listing_requests_count,
          details: client.detail_requests_count
        },
        photos: {
          downloaded: 0,
          image_urls_saved: run.items.where.not(image_url: [nil, '']).count
        }
      }

      run.update_columns(
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: client.detail_requests_count,
        candidates_found_count: run.items.count,
        outside_country_skipped_count: counts['skipped_outside_country'].to_i,
        duplicate_skipped_count: counts['skipped_duplicate'].to_i + counts['duplicate'].to_i,
        invalid_skipped_count: counts['skipped_invalid'].to_i,
        items_created_count: counts.values.sum,
        venues_created_count: counts['created'].to_i,
        venues_updated_count: counts['updated'].to_i,
        needs_review_count: run.dry_run? ? counts['dry_run'].to_i : counts['created'].to_i + counts['updated'].to_i,
        failed_count: counts['failed'].to_i,
        summary_payload: request_summary,
        updated_at: Time.current
      )
    end
  end
end
