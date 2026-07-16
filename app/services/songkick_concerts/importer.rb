module SongkickConcerts
  class Importer
    MAX_PAGES_PER_SOURCE = 25
    MAX_EVENTS = 10_000
    DEFAULT_SOURCE_PATHS = [
      '/metro-areas/28755-spain-madrid',
      '/metro-areas/28714-spain-barcelona',
      '/metro-areas/28802-spain-valencia',
      '/metro-areas/34871-spain-seville',
      '/metro-areas/28716-spain-bilbao',
      '/metro-areas/71431-spain-malaga',
      '/metro-areas/28809-spain-zaragoza',
      '/metro-areas/71561-spain-palma-de-mallorca',
      '/metro-areas/34604-spain-alicante',
      '/metro-areas/28739-spain-granada',
      '/metro-areas/105016-spain-san-sebastian',
      '/metro-areas/28768-spain-murcia'
    ].freeze
    DEFAULT_SOURCE_PATHS_TEXT = DEFAULT_SOURCE_PATHS.join("\n").freeze
    DEFAULT_SOURCE_URL = SongkickConcerts::Client::BASE_URL.freeze

    attr_reader :run, :client, :parser, :normalizer, :coordinate_resolver, :cover_resolver, :cover_attacher

    def initialize(
      run:,
      client: nil,
      parser: Parser.new,
      normalizer: Normalizer.new,
      coordinate_resolver: nil,
      image_downloader: nil,
      cover_resolver: nil,
      cover_attacher: BlackCoffeeConcertCoverAttachment
    )
      @run = run
      @client = client || Client.new(request_delay_seconds: run.request_delay_seconds)
      @parser = parser
      @normalizer = normalizer
      @coordinate_resolver = coordinate_resolver || CoordinateResolver.new(source_client: @client)
      @image_downloader = image_downloader
      @cover_resolver = cover_resolver || BlackCoffeeConcertCoverResolver.new(
        source_client: @client,
        source_parser: parser,
        source_normalizer: normalizer,
        downloader: image_downloader || BlackCoffeeImageDownloader.new(
          min_width: 240,
          min_height: 240,
          min_pixels: 57_600,
          validate_visual_content: true
        )
      )
      @cover_attacher = cover_attacher
      @images_downloaded_count = 0
      @source_cover_recovered_count = 0
      @search_cover_recovered_count = 0
      @no_cover_skipped_count = 0
      @non_concert_skipped_count = initial_non_concert_skipped_count
      @items_since_counts_refresh = 0
      @last_counts_refresh_at = monotonic_now
    end

    def self.enqueue!(created_by: nil, attributes:)
      run = BlackCoffeeConcertImportRun.create!(
        {
          source: BlackCoffeeConcertImportRun::SOURCE_SONGKICK,
          status: 'pending',
          source_url: DEFAULT_SOURCE_URL,
          source_paths: DEFAULT_SOURCE_PATHS_TEXT,
          created_by: created_by,
          import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_DASHBOARD
        }.merge(attributes)
      )
      BlackCoffeeConcertImportJob.perform_later(run.id)
      run
    end

    def perform!
      run.update!(
        status: 'running',
        started_at: run.started_at || Time.current,
        error_message: nil
      )

      process_source_paths
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

    def process_source_paths
      source_paths.each do |source_path|
        break if cancelled? || max_events_reached?

        process_source_path(source_path)
      rescue SongkickConcerts::Client::RequestError => e
        create_source_failure_item!(source_path, e)
        refresh_counts!
      end
    end

    def source_paths
      paths = run.source_paths_list
      paths.any? ? paths : DEFAULT_SOURCE_PATHS
    end

    def process_source_path(source_path)
      1.upto([run.max_pages_per_source.to_i, MAX_PAGES_PER_SOURCE].min) do |page_number|
        break if cancelled? || max_events_reached?

        html = client.fetch_metro_page(source_path, page: page_number)
        update_request_counts!

        raw_events = parser.parse_listing(html)
        break if raw_events.empty?

        raw_events.each do |raw_event|
          break if cancelled? || max_events_reached?

          process_raw_event(raw_event, source_path: source_path)
          refresh_counts_if_due!
        end
        refresh_counts!
        break unless parser.next_page?(html)
      end
    end

    def process_raw_event(raw_event, source_path:)
      normalized = normalizer.normalize(raw_event)
      create_skipped_item!(raw_event, normalized, 'skipped_outside_country', 'El concierto no pertenece a Espana.', source_path: source_path) && return if outside_country?(normalized)
      register_non_concert_skip! && return if non_concert?(normalized)
      unless normalized[:valid] || location_recoverable_from_detail?(normalized)
        create_skipped_item!(raw_event, normalized, 'skipped_invalid', 'Faltan datos minimos para crear el concierto.', source_path: source_path)
        return
      end
      create_skipped_item!(raw_event, normalized, 'skipped_past', 'El concierto ya finalizo.', source_path: source_path) && return if past_event?(normalized)

      duplicate = duplicate_venue_for(normalized)
      create_duplicate_item!(raw_event, normalized, duplicate, source_path: source_path) && return if duplicate.present?

      normalized, coordinate_result = resolve_coordinates(normalized)
      unless coordinate_result.resolved?
        create_item!(
          raw_event,
          normalized,
          status: 'pending_coordinates',
          source_path: source_path,
          error_message: coordinate_error_message(coordinate_result),
          warning_message: 'La direccion de Songkick se conservo, pero el concierto no se creo ni se publico sin coordenadas verificadas.'
        )
        return
      end

      if run.dry_run?
        create_item!(raw_event, normalized, status: 'dry_run', source_path: source_path)
      else
        create_venue_item!(raw_event, normalized, source_path: source_path)
      end
    rescue StandardError => e
      create_item!(
        raw_event,
        failure_context_for(raw_event, normalized),
        status: 'failed',
        source_path: source_path,
        error_message: "#{e.class} - #{e.message}"
      )
    end

    def outside_country?(normalized)
      normalized[:outside_country] || (normalized[:country_code].present? && normalized[:country_code] != run.strict_country_code)
    end

    def non_concert?(normalized)
      normalized[:non_concert_like]
    end

    def location_recoverable_from_detail?(normalized)
      normalized[:name].present? &&
        normalized[:country_code] == run.strict_country_code &&
        normalized[:source_url].to_s.match?(%r{\Ahttps://(?:www\.)?songkick\.com/concerts/\d+}) &&
        (normalized[:latitude].blank? || normalized[:longitude].blank?)
    end

    def register_non_concert_skip!
      @non_concert_skipped_count += 1
      true
    end

    def initial_non_concert_skipped_count
      return 0 unless run.has_attribute?(:non_concert_skipped_count)

      [
        run.non_concert_skipped_count.to_i,
        run.items.where(status: 'skipped_non_concert').count
      ].max
    end

    def past_event?(normalized)
      return false unless run.only_future?

      reference_date = normalized[:end_at]&.to_date || normalized[:start_at]&.to_date || normalized[:end_date] || normalized[:start_date]
      reference_date.present? && reference_date < Date.current
    end

    def resolve_coordinates(normalized)
      result = coordinate_resolver.resolve(normalized)
      enriched = normalized.merge(result.normalized_attributes)
      enriched[:coordinate_resolution_status] = result.status
      enriched[:coordinate_resolution_error_type] = result.error_type
      enriched[:coordinate_resolution_error_message] = result.error_message
      enriched[:locations] = resolved_location_metadata(enriched, result) if result.resolved?
      [enriched, result]
    end

    def resolved_location_metadata(normalized, result)
      location = Array(normalized[:locations]).first.to_h.deep_stringify_keys
      location.merge(
        'name' => normalized[:venue_name],
        'streetAddress' => result.street_address,
        'postalCode' => normalized[:postal_code],
        'city' => normalized[:city],
        'province' => normalized[:state],
        'country' => normalized[:country],
        'coordinates' => {
          'latitude' => normalized[:latitude],
          'longitude' => normalized[:longitude]
        },
        'coordinatesSource' => normalized[:coordinates_source],
        'coordinatesConfidence' => normalized[:coordinates_confidence]
      ).compact.then { |entry| [entry] }
    end

    def coordinate_error_message(result)
      prefix = result.ambiguous? ? 'Coordenadas ambiguas' : 'Coordenadas no resueltas'
      "#{prefix} (#{result.error_type.presence || result.status}): #{result.error_message.presence || 'La direccion no produjo una coincidencia segura.'}"
    end

    def max_events_reached?
      run.items.count >= run.max_events.to_i
    end

    def duplicate_venue_for(normalized)
      concert_scope = Venue.where(category: 'concierto')
      source_scope = Venue.column_names.include?('external_source') ? concert_scope.where(external_source: SongkickConcerts::Normalizer::SOURCE) : Venue.none
      return source_scope.find_by(external_source_id: normalized[:source_event_id]) if normalized[:source_event_id].present? && Venue.column_names.include?('external_source_id')
      return source_scope.find_by(source_fingerprint: normalized[:fingerprint]) if normalized[:fingerprint].present? && Venue.column_names.include?('source_fingerprint')
      return concert_scope.find_by(event_dedupe_key: normalized[:event_dedupe_key]) if normalized[:event_dedupe_key].present? && Venue.column_names.include?('event_dedupe_key')

      fallback = concert_scope
                 .where('LOWER(name) = ? AND LOWER(city) = ?', normalized[:name].to_s.downcase, normalized[:city].to_s.downcase)
                 .where(festival_start_date: normalized[:start_date])
      fallback = fallback.where('LOWER(festival_venue_name) = ?', normalized[:venue_name].to_s.downcase) if normalized[:venue_name].present? && Venue.column_names.include?('festival_venue_name')
      fallback.first
    end

    def create_duplicate_item!(raw_event, normalized, duplicate, source_path:)
      create_item!(
        raw_event,
        normalized,
        status: 'skipped_duplicate',
        source_path: source_path,
        venue: duplicate,
        error_message: "Ya existe el local #{duplicate.id}."
      )
    end

    def create_skipped_item!(raw_event, normalized, status, message, source_path:)
      create_item!(raw_event, normalized, status: status, source_path: source_path, error_message: message)
    end

    def create_source_failure_item!(source_path, error)
      create_item!(
        {},
        source_failure_context_for(source_path),
        status: 'failed',
        source_path: source_path,
        error_message: "#{error.class} - #{error.message}"
      )
    end

    def source_failure_context_for(source_path)
      {
        source_url: source_url_for_path(source_path),
        source_event_id: nil,
        fingerprint: nil,
        name: "Fuente Songkick #{source_path}",
        venue_name: nil,
        city: nil,
        state: nil,
        country: nil,
        country_code: nil,
        start_at: nil,
        end_at: nil,
        start_date: nil,
        end_date: nil,
        event_dedupe_key: nil,
        image_url: nil,
        latitude: nil,
        longitude: nil,
        coordinates_source: nil,
        coordinates_confidence: nil,
        source_description: nil,
        source_description_language: nil,
        source_description_status: 'not_found',
        official_url: nil,
        ticket_url: nil
      }
    end

    def source_url_for_path(source_path)
      return source_path if source_path.to_s.start_with?('http')

      URI.join(SongkickConcerts::Client::BASE_URL, source_path.to_s).to_s
    rescue URI::InvalidURIError
      source_path
    end

    def failure_context_for(raw_event, normalized)
      return normalized if normalized.present?
      return {} unless raw_event.is_a?(Hash)

      raw = raw_event.deep_stringify_keys
      location = raw['location'].is_a?(Hash) ? raw['location'] : {}
      address = location['address'].is_a?(Hash) ? location['address'] : {}

      {
        source_url: raw['url'].presence || raw['@id'].to_s.sub(/#event\z/, '').presence,
        source_event_id: raw['@id'],
        name: raw['name'],
        venue_name: location['name'],
        city: address['addressLocality'],
        state: address['addressRegion'],
        country: address['addressCountry'],
        start_at: raw['startDate'],
        end_at: raw['endDate'],
        start_date: raw['startDate'],
        end_date: raw['endDate']
      }
    end

    def create_venue_item!(raw_event, normalized, source_path:)
      cover_result = cover_resolver.resolve_for_import(normalized)
      unless cover_result.recovered?
        return create_pending_cover_venue_item!(
          raw_event,
          normalized,
          source_path: source_path,
          cover_result: cover_result
        )
      end

      venue = nil
      ActiveRecord::Base.transaction do
        venue = Venue.create!(venue_attributes(normalized))
        venue_image = attach_verified_cover!(
          venue: venue,
          download: cover_result.download,
          resolution_source: cover_result.resolution_source,
          source_url: cover_result.image_url,
          provenance: {
            source_page_url: cover_result.page_url,
            original_image_url: cover_result.image_url,
            resolution_source: cover_result.resolution_source,
            confidence: cover_result.confidence,
            evidence: cover_result.evidence
          }.compact
        )
        cover_resolver.record_attachment(result: cover_result, venue_image: venue_image) if cover_resolver.respond_to?(:record_attachment)
        create_item!(
          raw_event,
          normalized,
          status: 'created',
          source_path: source_path,
          venue: venue,
          cover_result: cover_result
        )
      end
      register_recovered_cover!(cover_result)
    rescue BlackCoffeeConcertCoverAttachment::PersistenceError => e
      create_pending_cover_venue_item!(
        raw_event,
        normalized,
        source_path: source_path,
        cover_result: cover_result,
        error_message: "No se pudo persistir la portada recuperada: #{e.message}"
      )
    rescue ActiveRecord::RecordNotUnique
      duplicate = duplicate_venue_for(normalized)
      if duplicate.present?
        create_duplicate_item!(raw_event, normalized, duplicate, source_path: source_path)
      else
        create_item!(raw_event, normalized, status: 'failed', source_path: source_path, error_message: 'Duplicado protegido por indice, pero no se pudo localizar el venue existente.')
      end
    end

    def create_pending_cover_venue_item!(raw_event, normalized, source_path:, cover_result:, error_message: nil)
      @no_cover_skipped_count += 1
      venue = nil
      ActiveRecord::Base.transaction do
        venue = Venue.create!(venue_attributes(normalized, force_pending_cover: true))
        create_item!(
          raw_event,
          normalized,
          status: 'created_pending_cover',
          source_path: source_path,
          venue: venue,
          error_message: error_message.presence || cover_result.error_message.presence || 'No se encontro una portada segura; el concierto queda oculto y pendiente de revision.',
          warning_message: 'No se publico ninguna imagen porque la identidad o la disponibilidad de los candidatos no fue concluyente.',
          cover_result: cover_result
        )
      end
      venue
    rescue ActiveRecord::RecordNotUnique
      duplicate = duplicate_venue_for(normalized)
      if duplicate.present?
        create_duplicate_item!(raw_event, normalized, duplicate, source_path: source_path)
      else
        create_item!(raw_event, normalized, status: 'failed', source_path: source_path, error_message: 'Duplicado protegido por indice, pero no se pudo localizar el venue existente.')
      end
    end

    def attach_verified_cover!(**attributes)
      venue = attributes.fetch(:venue)
      venue_image = cover_attacher.attach!(**attributes)
      BlackCoffeeConcertCoverAttachment.verify_persisted!(venue: venue, venue_image: venue_image)
    rescue ActiveRecord::RecordNotUnique
      raise
    rescue BlackCoffeeConcertCoverAttachment::PersistenceError
      raise
    rescue StandardError => e
      raise BlackCoffeeConcertCoverAttachment::PersistenceError,
            "#{e.class} - #{e.message}"
    end

    def register_recovered_cover!(cover_result)
      @images_downloaded_count += 1
      if cover_result.respond_to?(:external?) && cover_result.external?
        @search_cover_recovered_count += 1
      else
        @source_cover_recovered_count += 1
      end
    end

    def venue_attributes(normalized, force_pending_cover: false)
      attrs = {
        name: normalized[:name],
        category: 'concierto',
        description: normalized[:source_description].presence || 'Descripcion pendiente de revisar.',
        address: normalized[:address],
        city: normalized[:city],
        latitude: normalized[:latitude],
        longitude: normalized[:longitude],
        featured: false,
        tags: concert_tags(normalized)
      }
      attrs[:state] = normalized[:state] if Venue.column_names.include?('state')
      attrs[:postal_code] = normalized[:postal_code] if Venue.column_names.include?('postal_code')
      attrs[:country] = normalized[:country].presence || 'Espana' if Venue.column_names.include?('country')
      attrs[:country_code] = 'ES' if Venue.column_names.include?('country_code')
      attrs[:review_status] = (!force_pending_cover && run.publish_immediately?) ? Venue::REVIEW_STATUS_APPROVED : Venue::REVIEW_STATUS_PENDING if Venue.column_names.include?('review_status')
      attrs[:visible] = !force_pending_cover && run.publish_immediately? if Venue.column_names.include?('visible')
      attrs[:payment_current] = true if Venue.column_names.include?('payment_current')
      attrs[:internal_test] = false if Venue.column_names.include?('internal_test')
      attrs[:external_source] = SongkickConcerts::Normalizer::SOURCE if Venue.column_names.include?('external_source')
      attrs[:external_source_url] = normalized[:source_url] if Venue.column_names.include?('external_source_url')
      attrs[:external_source_id] = normalized[:source_event_id] if Venue.column_names.include?('external_source_id')
      attrs[:source_fingerprint] = normalized[:fingerprint] if Venue.column_names.include?('source_fingerprint')
      attrs[:event_start_at] = normalized[:start_at] if Venue.column_names.include?('event_start_at')
      attrs[:event_end_at] = normalized[:end_at] if Venue.column_names.include?('event_end_at')
      attrs[:event_status] = Venue::EVENT_STATUS_UPCOMING if Venue.column_names.include?('event_status')
      attrs[:event_import_origin] = run.cron_import? ? Venue::EVENT_IMPORT_ORIGIN_CRON : Venue::EVENT_IMPORT_ORIGIN_DASHBOARD if Venue.column_names.include?('event_import_origin')
      attrs[:event_dedupe_key] = normalized[:event_dedupe_key] if Venue.column_names.include?('event_dedupe_key')
      attrs[:festival_start_date] = normalized[:start_date] if Venue.column_names.include?('festival_start_date')
      attrs[:festival_end_date] = normalized[:end_date] if Venue.column_names.include?('festival_end_date')
      attrs[:festival_metadata] = concert_metadata(normalized) if Venue.column_names.include?('festival_metadata')
      attrs[:coordinates_source] = normalized[:coordinates_source] if Venue.column_names.include?('coordinates_source')
      attrs[:coordinates_confidence] = normalized[:coordinates_confidence] if Venue.column_names.include?('coordinates_confidence')
      attrs[:source_description] = normalized[:source_description] if Venue.column_names.include?('source_description')
      attrs[:source_description_language] = normalized[:source_description_language] if Venue.column_names.include?('source_description_language')
      attrs[:source_description_status] = normalized[:source_description_status] if Venue.column_names.include?('source_description_status')
      attrs[:official_url] = normalized[:official_url] if Venue.column_names.include?('official_url')
      attrs[:ticket_url] = normalized[:ticket_url] if Venue.column_names.include?('ticket_url')
      attrs[:festival_venue_name] = normalized[:venue_name] if Venue.column_names.include?('festival_venue_name')
      attrs
    end

    def concert_tags(normalized)
      (%w[concierto concert songkick] + Array(normalized[:genres]).first(6)).compact.uniq
    end

    def concert_metadata(normalized)
      {
        event_kind: 'concert',
        raw_title: normalized[:edition_title],
        event_status: normalized[:event_status],
        performers: normalized[:performers],
        performer_details: normalized[:performer_details],
        primary_artist_name: normalized[:artist_name],
        source_artist_id: normalized[:source_artist_id],
        genres: normalized[:genres],
        offers: normalized[:offers],
        locations: normalized[:locations],
        venue_name: normalized[:venue_name],
        source_venue_id: normalized[:source_venue_id],
        coordinates_evidence: normalized[:coordinates_evidence],
        source: SongkickConcerts::Normalizer::SOURCE
      }
    end

    def create_item!(raw_event, normalized, status:, source_path:, venue: nil, error_message: nil, warning_message: nil, cover_result: nil)
      attributes = {
        venue: venue,
        status: status,
        source: SongkickConcerts::Normalizer::SOURCE,
        source_path: source_path,
        source_url: normalized[:source_url],
        source_event_id: normalized[:source_event_id],
        fingerprint: normalized[:fingerprint],
        event_dedupe_key: normalized[:event_dedupe_key],
        name: normalized[:name],
        venue_name: normalized[:venue_name],
        city: normalized[:city],
        state: normalized[:state],
        country: normalized[:country],
        country_code: normalized[:country_code],
        start_at: normalized[:start_at],
        end_at: normalized[:end_at],
        start_date: normalized[:start_date],
        end_date: normalized[:end_date],
        image_url: cover_result&.image_url.presence || normalized[:image_url],
        latitude: normalized[:latitude],
        longitude: normalized[:longitude],
        coordinates_source: normalized[:coordinates_source],
        coordinates_confidence: normalized[:coordinates_confidence],
        source_description: normalized[:source_description],
        source_description_language: normalized[:source_description_language],
        source_description_status: normalized[:source_description_status],
        official_url: normalized[:official_url],
        ticket_url: normalized[:ticket_url],
        warning_message: warning_message,
        error_message: error_message,
        raw_payload: raw_event,
        normalized_payload: normalized.except(:raw_payload)
      }
      if BlackCoffeeConcertImportItem.column_names.include?('image_resolution_source')
        attributes[:image_resolution_source] = cover_result&.resolution_source
        attributes[:image_resolution_confidence] = cover_result&.confidence
        attributes[:image_resolution_evidence] = cover_result&.evidence
      end
      run.items.create!(attributes)
    end

    def update_request_counts!
      updates = {
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: cover_resolver.source_requests_count,
        updated_at: Time.current
      }
      updates[:image_search_requests_count] = cover_resolver.search_requests_count if run.has_attribute?(:image_search_requests_count) && cover_resolver.respond_to?(:search_requests_count)
      updates[:image_download_requests_count] = cover_resolver.image_download_requests_count if run.has_attribute?(:image_download_requests_count)
      run.update_columns(updates)
    end

    def refresh_counts_if_due!
      @items_since_counts_refresh += 1
      elapsed = monotonic_now - @last_counts_refresh_at
      return if @items_since_counts_refresh < 5 && elapsed < 2.5

      refresh_counts!
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
      concert_items = run.items.where.not(status: %w[skipped_non_concert skipped_festival])
      request_summary = {
        source: SongkickConcerts::Normalizer::SOURCE,
        source_url: run.source_url,
        source_paths: source_paths,
        requests: {
          robots: client.robots_requests_count,
          listing: client.listing_requests_count,
          details: cover_resolver.source_requests_count,
          image_search: cover_resolver.respond_to?(:search_requests_count) ? cover_resolver.search_requests_count : 0,
          image_downloads: cover_resolver.image_download_requests_count,
          geocoding: coordinate_resolver.respond_to?(:requests_count) ? coordinate_resolver.requests_count : 0
        },
        coordinates: {
          resolved: run.items.where(status: %w[dry_run created created_pending_cover]).where.not(latitude: nil).where.not(longitude: nil).count,
          pending: counts['pending_coordinates'].to_i,
          geocoding_requests: coordinate_resolver.respond_to?(:requests_count) ? coordinate_resolver.requests_count : 0
        },
        photos: {
          downloaded: @images_downloaded_count,
          recovered_from_source: @source_cover_recovered_count,
          recovered_from_external_sources: @search_cover_recovered_count,
          concerts_pending_without_cover: counts['created_pending_cover'].to_i
        }
      }

      updates = {
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: cover_resolver.source_requests_count,
        candidates_found_count: concert_items.count,
        outside_country_skipped_count: counts['skipped_outside_country'].to_i,
        festival_skipped_count: counts['skipped_festival'].to_i,
        non_concert_skipped_count: @non_concert_skipped_count,
        duplicate_skipped_count: counts['skipped_duplicate'].to_i,
        invalid_skipped_count: counts['skipped_invalid'].to_i,
        past_skipped_count: counts['skipped_past'].to_i,
        images_downloaded_count: @images_downloaded_count,
        items_created_count: concert_items.count,
        venues_created_count: counts['created'].to_i + counts['created_pending_cover'].to_i,
        needs_review_count: run.dry_run? ? counts['dry_run'].to_i + counts['pending_coordinates'].to_i : counts['created'].to_i + counts['created_pending_cover'].to_i + counts['pending_coordinates'].to_i,
        failed_count: counts['failed'].to_i,
        summary_payload: request_summary,
        updated_at: Time.current
      }
      if run.has_attribute?(:source_cover_recovered_count)
        updates[:source_cover_recovered_count] = @source_cover_recovered_count
        updates[:search_cover_recovered_count] = @search_cover_recovered_count
        updates[:no_cover_skipped_count] = counts['created_pending_cover'].to_i + counts['skipped_no_cover'].to_i
        updates[:image_search_requests_count] = cover_resolver.respond_to?(:search_requests_count) ? cover_resolver.search_requests_count : 0
        updates[:image_download_requests_count] = cover_resolver.image_download_requests_count
      end
      run.update_columns(updates)
      @items_since_counts_refresh = 0
      @last_counts_refresh_at = monotonic_now
    end
  end
end
