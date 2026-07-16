class BlackCoffeeConcertCoverResolver
  Result = Struct.new(
    :status,
    :download,
    :resolution_source,
    :image_url,
    :page_url,
    :confidence,
    :evidence,
    :error_type,
    :error_message,
    keyword_init: true
  ) do
    def recovered?
      status == 'recovered' && download&.ok?
    end

    def missing?
      status == 'missing'
    end

    def retryable?
      status == 'retryable_error'
    end

    def unavailable?
      status == 'unavailable'
    end
  end

  MAX_SOURCE_IMAGE_CANDIDATES = 3
  attr_reader :source_client

  def initialize(
    source_client: nil,
    source_parser: SongkickConcerts::Parser.new,
    source_normalizer: SongkickConcerts::Normalizer.new,
    downloader: BlackCoffeeImageDownloader.new
  )
    @source_client = source_client || SongkickConcerts::Client.new
    @source_parser = source_parser
    @source_normalizer = source_normalizer
    @downloader = downloader
    @image_download_requests_count = 0
  end

  def resolve_for_venue(venue)
    event = event_from_venue(venue)
    preferred_urls = venue_source_image_urls(venue)
    resolve(event: event, preferred_urls: preferred_urls)
  end

  def resolve_for_import(normalized)
    event = event_from_normalized(normalized)
    resolve(event: event, preferred_urls: [normalized[:image_url]])
  end

  def source_requests_count
    source_client.respond_to?(:detail_requests_count) ? source_client.detail_requests_count.to_i : 0
  end

  def source_total_requests_count
    source_requests_count + (source_client.respond_to?(:robots_requests_count) ? source_client.robots_requests_count.to_i : 0)
  end

  attr_reader :image_download_requests_count

  private

  attr_reader :source_parser, :source_normalizer, :downloader

  def resolve(event:, preferred_urls:)
    attempts = []
    metadata_result = download_first(
      urls: preferred_urls,
      resolution_source: 'source_metadata',
      page_url: event[:source_url],
      confidence: 100,
      evidence: { match: 'stored_source_metadata' }
    )
    return metadata_result if metadata_result&.recovered?
    attempts << metadata_result if metadata_result

    page_result = resolve_from_source_page(event)
    return page_result if page_result&.recovered?
    attempts << page_result if page_result

    unresolved_attempt = attempts.find { |attempt| attempt.retryable? || attempt.unavailable? }
    status = unresolved_attempt ? unresolved_attempt.status : 'missing'
    Result.new(
      status: status,
      error_type: unresolved_attempt&.error_type || attempts.last&.error_type || 'no_cover_found',
      error_message: attempts.filter_map(&:error_message).uniq.join(' | ').presence || 'No se encontro una portada verificable para este concierto.',
      evidence: {
        source_page_attempted: event[:source_url].present?,
        attempts: attempts.map { |attempt| attempt_evidence(attempt) }
      }
    )
  end

  def resolve_from_source_page(event)
    return missing_result('missing_source_url', 'El concierto no conserva una URL de origen.') if event[:source_url].blank?

    html = source_client.fetch_event_page(event[:source_url])
    raw_event = matching_source_event(source_parser.parse_listing(html), event)
    return missing_result('source_event_mismatch', 'La ficha de origen no coincide con el concierto guardado.') unless raw_event

    normalized = source_normalizer.normalize(raw_event)
    urls = [normalized[:image_url]] + source_parser.page_image_urls(html)
    result = download_first(
      urls: urls,
      resolution_source: 'source_page',
      page_url: event[:source_url],
      confidence: 100,
      evidence: { match: 'exact_source_event' }
    )
    result || missing_result('source_without_working_image', 'La ficha exacta de Songkick no ofrece una imagen descargable.')
  rescue SongkickConcerts::Client::RobotsBlockedError => e
    unavailable_result('source_blocked_by_robots', e.message)
  rescue SongkickConcerts::Client::RequestError => e
    return missing_result('source_event_not_found', e.message) if e.not_found?
    return retryable_result('source_request_error', e.message) if e.retryable?

    unavailable_result('source_request_blocked', e.message)
  end

  def download_first(urls:, resolution_source:, page_url:, confidence:, evidence:)
    candidates = Array(urls).map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(MAX_SOURCE_IMAGE_CANDIDATES)
    return nil if candidates.empty?

    failures = []
    candidates.each do |url|
      @image_download_requests_count += 1
      download = downloader.download(url)
      unless download.ok?
        failures << download
        next
      end

      return Result.new(
        status: 'recovered',
        download: download,
        resolution_source: resolution_source,
        image_url: url,
        page_url: page_url,
        confidence: confidence,
        evidence: evidence
      )
    end

    retryable_failure = failures.find { |failure| retryable_download_failure?(failure) }
    failure = retryable_failure || failures.last
    Result.new(
      status: retryable_failure ? 'retryable_error' : 'missing',
      resolution_source: resolution_source,
      page_url: page_url,
      confidence: confidence,
      evidence: evidence.merge(candidate_urls_checked: candidates.size),
      error_type: failure&.error_type.presence || 'image_download_failed',
      error_message: failure&.error_message.presence || 'Las URLs de portada no devolvieron una imagen valida.'
    )
  end

  def matching_source_event(raw_events, event)
    Array(raw_events).find do |raw_event|
      normalized = source_normalizer.normalize(raw_event)
      source_id_matches?(normalized, event) || event_identity_matches?(normalized, event)
    end
  end

  def source_id_matches?(normalized, event)
    event[:source_event_id].present? && normalized[:source_event_id].to_s == event[:source_event_id].to_s
  end

  def event_identity_matches?(normalized, event)
    return false if event[:date].blank?

    canonical_text(normalized[:name]) == canonical_text(event[:name]) &&
      normalized[:start_date].present? &&
      normalized[:start_date].to_date == event[:date].to_date
  end

  def event_from_venue(venue)
    {
      name: venue.name,
      date: venue.event_start_at.presence || venue.festival_start_date,
      city: venue.city,
      venue_name: venue.respond_to?(:festival_venue_name) ? venue.festival_venue_name : nil,
      source_url: venue.respond_to?(:external_source_url) ? venue.external_source_url : nil,
      source_event_id: venue.respond_to?(:external_source_id) ? venue.external_source_id : nil
    }
  end

  def event_from_normalized(normalized)
    {
      name: normalized[:name],
      date: normalized[:start_at].presence || normalized[:start_date],
      city: normalized[:city],
      venue_name: normalized[:venue_name],
      source_url: normalized[:source_url],
      source_event_id: normalized[:source_event_id]
    }
  end

  def venue_source_image_urls(venue)
    existing_urls = venue.venue_images.to_a.map(&:url)
    imported_urls = venue.concert_import_items.where.not(image_url: [nil, '']).recent_first.limit(3).pluck(:image_url)
    (existing_urls + imported_urls).compact.uniq
  end

  def canonical_text(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
  end

  def missing_result(error_type, message)
    Result.new(status: 'missing', error_type: error_type, error_message: message)
  end

  def retryable_result(error_type, message)
    Result.new(status: 'retryable_error', error_type: error_type, error_message: message)
  end

  def unavailable_result(error_type, message)
    Result.new(status: 'unavailable', error_type: error_type, error_message: message)
  end

  def retryable_download_failure?(failure)
    return true if %w[timeout network_error unknown_error empty_response].include?(failure.error_type.to_s)

    failure.http_status.to_i == 429 || failure.http_status.to_i >= 500
  end

  def attempt_evidence(attempt)
    {
      status: attempt.status,
      source: attempt.resolution_source,
      error_type: attempt.error_type,
      error_message: attempt.error_message
    }.compact
  end
end
