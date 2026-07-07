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

    attr_reader :run, :client, :parser, :normalizer

    def initialize(run:, client: nil, parser: Parser.new, normalizer: Normalizer.new, image_downloader: nil)
      @run = run
      @client = client || Client.new(request_delay_seconds: run.request_delay_seconds)
      @parser = parser
      @normalizer = normalizer
      @image_downloader = image_downloader
      @images_downloaded_count = 0
    end

    def self.enqueue!(created_by:, attributes:)
      run = BlackCoffeeConcertImportRun.create!(
        {
          source: BlackCoffeeConcertImportRun::SOURCE_SONGKICK,
          status: 'pending',
          source_url: DEFAULT_SOURCE_URL,
          source_paths: DEFAULT_SOURCE_PATHS_TEXT,
          created_by: created_by
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
        end
        refresh_counts!
        break unless parser.next_page?(html)
      end
    end

    def process_raw_event(raw_event, source_path:)
      normalized = normalizer.normalize(raw_event)
      create_skipped_item!(raw_event, normalized, 'skipped_outside_country', 'El concierto no pertenece a Espana.', source_path: source_path) && return if outside_country?(normalized)
      create_skipped_item!(raw_event, normalized, 'skipped_festival', 'La fuente lo marca como festival; lo gestiona FanMusicFest.', source_path: source_path) && return if skip_festival?(normalized)
      create_skipped_item!(raw_event, normalized, 'skipped_invalid', 'Faltan datos minimos para crear el concierto.', source_path: source_path) && return unless normalized[:valid]
      create_skipped_item!(raw_event, normalized, 'skipped_past', 'El concierto ya finalizo.', source_path: source_path) && return if past_event?(normalized)

      duplicate = duplicate_venue_for(normalized)
      create_duplicate_item!(raw_event, normalized, duplicate, source_path: source_path) && return if duplicate.present?

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

    def skip_festival?(normalized)
      normalized[:festival_like] && !run.include_festivals?
    end

    def past_event?(normalized)
      return false unless run.only_future?

      reference_date = normalized[:end_date] || normalized[:start_date]
      reference_date.present? && reference_date < Date.current
    end

    def max_events_reached?
      run.items.count >= run.max_events.to_i
    end

    def duplicate_venue_for(normalized)
      source_scope = Venue.column_names.include?('external_source') ? Venue.where(external_source: SongkickConcerts::Normalizer::SOURCE) : Venue.none
      return source_scope.find_by(external_source_id: normalized[:source_event_id]) if normalized[:source_event_id].present? && Venue.column_names.include?('external_source_id')
      return source_scope.find_by(source_fingerprint: normalized[:fingerprint]) if normalized[:fingerprint].present? && Venue.column_names.include?('source_fingerprint')

      Venue.where(category: 'concierto')
           .where('LOWER(name) = ? AND LOWER(city) = ?', normalized[:name].to_s.downcase, normalized[:city].to_s.downcase)
           .where(festival_start_date: normalized[:start_date])
           .first
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
        start_date: nil,
        end_date: nil,
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
        start_date: raw['startDate'],
        end_date: raw['endDate']
      }
    end

    def create_venue_item!(raw_event, normalized, source_path:)
      venue = nil
      venue_image = nil
      ActiveRecord::Base.transaction do
        venue = Venue.create!(venue_attributes(normalized))
        venue_image = build_venue_image(venue, normalized)
        create_item!(raw_event, normalized, status: 'created', source_path: source_path, venue: venue)
      end

      internalize_image!(venue_image)
    end

    def build_venue_image(venue, normalized)
      image_url = normalized[:image_url].to_s.strip
      return nil if image_url.blank?

      venue.venue_images.create!(
        url: image_url,
        source: SongkickConcerts::Normalizer::SOURCE,
        position: 0
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Songkick skipping invalid image url for venue #{venue.id}: #{e.message}")
      nil
    end

    def internalize_image!(venue_image)
      return unless venue_image
      return unless run.download_images?

      result = BlackCoffeeVenueImageLinkConverter.convert_image!(
        image: venue_image,
        downloader: image_downloader
      )
      @images_downloaded_count += 1 if result&.status == 'converted'
      result
    rescue StandardError => e
      Rails.logger.warn("Songkick image download failed for venue_image #{venue_image.id}: #{e.class} - #{e.message}")
      nil
    end

    def image_downloader
      @image_downloader ||= BlackCoffeeImageDownloader.new
    end

    def venue_attributes(normalized)
      attrs = {
        name: normalized[:name],
        category: 'concierto',
        description: nil,
        address: normalized[:address],
        city: normalized[:city],
        latitude: normalized[:latitude],
        longitude: normalized[:longitude],
        featured: false,
        tags: concert_tags(normalized)
      }
      attrs[:state] = normalized[:state] if Venue.column_names.include?('state')
      attrs[:country] = normalized[:country].presence || 'Espana' if Venue.column_names.include?('country')
      attrs[:country_code] = 'ES' if Venue.column_names.include?('country_code')
      attrs[:review_status] = run.auto_publish? ? Venue::REVIEW_STATUS_APPROVED : Venue::REVIEW_STATUS_PENDING if Venue.column_names.include?('review_status')
      attrs[:visible] = true if Venue.column_names.include?('visible')
      attrs[:payment_current] = true if Venue.column_names.include?('payment_current')
      attrs[:internal_test] = false if Venue.column_names.include?('internal_test')
      attrs[:external_source] = SongkickConcerts::Normalizer::SOURCE if Venue.column_names.include?('external_source')
      attrs[:external_source_url] = normalized[:source_url] if Venue.column_names.include?('external_source_url')
      attrs[:external_source_id] = normalized[:source_event_id] if Venue.column_names.include?('external_source_id')
      attrs[:source_fingerprint] = normalized[:fingerprint] if Venue.column_names.include?('source_fingerprint')
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
        genres: normalized[:genres],
        offers: normalized[:offers],
        locations: normalized[:locations],
        venue_name: normalized[:venue_name],
        source: SongkickConcerts::Normalizer::SOURCE
      }
    end

    def create_item!(raw_event, normalized, status:, source_path:, venue: nil, error_message: nil, warning_message: nil)
      run.items.create!(
        venue: venue,
        status: status,
        source: SongkickConcerts::Normalizer::SOURCE,
        source_path: source_path,
        source_url: normalized[:source_url],
        source_event_id: normalized[:source_event_id],
        fingerprint: normalized[:fingerprint],
        name: normalized[:name],
        venue_name: normalized[:venue_name],
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
        warning_message: warning_message,
        error_message: error_message,
        raw_payload: raw_event,
        normalized_payload: normalized.except(:raw_payload)
      )
    end

    def update_request_counts!
      run.update_columns(
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: 0,
        updated_at: Time.current
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
        source: SongkickConcerts::Normalizer::SOURCE,
        source_url: run.source_url,
        source_paths: source_paths,
        requests: {
          robots: client.robots_requests_count,
          listing: client.listing_requests_count,
          details: 0
        },
        photos: {
          downloaded: @images_downloaded_count,
          image_urls_saved: run.items.where.not(image_url: [nil, '']).count
        }
      }

      run.update_columns(
        robots_requests_count: client.robots_requests_count,
        listing_requests_count: client.listing_requests_count,
        detail_requests_count: 0,
        candidates_found_count: run.items.count,
        outside_country_skipped_count: counts['skipped_outside_country'].to_i,
        festival_skipped_count: counts['skipped_festival'].to_i,
        duplicate_skipped_count: counts['skipped_duplicate'].to_i,
        invalid_skipped_count: counts['skipped_invalid'].to_i,
        past_skipped_count: counts['skipped_past'].to_i,
        images_downloaded_count: @images_downloaded_count,
        items_created_count: counts.values.sum,
        venues_created_count: counts['created'].to_i,
        needs_review_count: run.dry_run? ? counts['dry_run'].to_i : counts['created'].to_i,
        failed_count: counts['failed'].to_i,
        summary_payload: request_summary,
        updated_at: Time.current
      )
    end
  end
end
