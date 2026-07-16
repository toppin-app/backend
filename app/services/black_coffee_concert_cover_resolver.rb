require 'nokogiri'
require 'uri'

class BlackCoffeeConcertCoverResolver
  Result = Struct.new(
    :status,
    :download,
    :resolution_source,
    :source_kind,
    :image_url,
    :page_url,
    :confidence,
    :evidence,
    :error_type,
    :error_message,
    :artist_identity_key,
    :identifiers,
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

    def ambiguous?
      status == 'ambiguous'
    end

    def external?
      source_kind == 'external'
    end

    def cache?
      source_kind == 'cache'
    end
  end

  MAX_SOURCE_IMAGE_CANDIDATES = 12
  MAX_EXTERNAL_IMAGE_CANDIDATES = 5

  attr_reader :source_client, :external_search

  def initialize(
    source_client: nil,
    source_parser: SongkickConcerts::Parser.new,
    source_normalizer: SongkickConcerts::Normalizer.new,
    downloader: nil,
    external_search: nil,
    cache_store: nil,
    external_search_enabled: true,
    logger: Rails.logger
  )
    @source_client = source_client || SongkickConcerts::Client.new
    @source_parser = source_parser
    @source_normalizer = source_normalizer
    @downloader = downloader || BlackCoffeeImageDownloader.new(min_width: 240, min_height: 240)
    @external_search = external_search || BlackCoffeeConcertCoverSearch::Coordinator.new(logger: logger)
    @cache_store = cache_store || BlackCoffeeConcertArtistImageCacheStore.new(logger: logger)
    @external_search_enabled = external_search_enabled
    @logger = logger
    @image_download_requests_count = 0
  end

  def resolve_for_venue(venue)
    event = event_from_venue(venue)
    preferred_urls = venue_source_image_urls(venue)
    resolve(event: event, preferred_candidates: preferred_urls)
  end

  def resolve_for_import(normalized)
    event = event_from_normalized(normalized)
    candidates = Array(normalized[:image_candidates]).presence || Array(normalized[:image_urls]).presence || [normalized[:image_url]]
    resolve(event: event, preferred_candidates: candidates)
  end

  def record_attachment(result:, venue_image:)
    return unless result&.artist_identity_key.present? && venue_image.present?

    cache_store.link_attachment!(identity_key: result.artist_identity_key, venue_image: venue_image)
  end

  def source_requests_count
    source_client.respond_to?(:detail_requests_count) ? source_client.detail_requests_count.to_i : 0
  end

  def source_total_requests_count
    source_requests_count + (source_client.respond_to?(:robots_requests_count) ? source_client.robots_requests_count.to_i : 0)
  end

  def search_requests_count
    external_search.respond_to?(:requests_count) ? external_search.requests_count.to_i : 0
  end

  attr_reader :image_download_requests_count

  private

  attr_reader :source_parser, :source_normalizer, :downloader, :cache_store, :logger, :external_search_enabled

  def resolve(event:, preferred_candidates:)
    attempts = []
    cache_lookup = cache_store.lookup(event)

    if cache_lookup&.reusable?
      result = Result.new(
        status: 'recovered',
        download: cache_lookup.download,
        resolution_source: 'artist_cache',
        source_kind: 'cache',
        image_url: cache_lookup.record.image_url,
        page_url: cache_lookup.record.source_page_url,
        confidence: cache_lookup.record.confidence,
        evidence: cache_lookup.record.evidence.to_h.merge(cache_hit: true, cached_venue_image_id: cache_lookup.record.venue_image_id),
        artist_identity_key: cache_lookup.record.identity_key,
        identifiers: cache_identifiers(cache_lookup.record)
      )
      log_selection(event, result)
      return result
    end

    metadata_result = download_first(
      candidates: preferred_candidates,
      resolution_source: 'source_metadata',
      source_kind: 'source',
      page_url: event[:source_url],
      confidence: 100,
      evidence: { match: 'stored_source_metadata' },
      limit: MAX_SOURCE_IMAGE_CANDIDATES
    )
    return finalize_recovered(event, metadata_result) if metadata_result&.recovered?
    attempts << metadata_result if metadata_result

    page_result = resolve_from_source_page(event)
    return finalize_recovered(event, page_result) if page_result&.recovered?
    attempts << page_result if page_result

    cached_result = resolve_from_cached_record(cache_lookup&.record)
    return finalize_recovered(event, cached_result, persist: false) if cached_result&.recovered?
    attempts << cached_result if cached_result

    external_result = resolve_from_external_sources(event, cache_lookup&.record)
    return finalize_recovered(event, external_result) if external_result&.recovered?
    attempts << external_result if external_result

    finalize_unresolved(event, attempts)
  end

  def resolve_from_source_page(event)
    return missing_result('missing_source_url', 'El concierto no conserva una URL de origen.') if event[:source_url].blank?

    html = source_client.fetch_event_page(event[:source_url])
    raw_events = source_parser.parse_listing(html)
    raw_event = matching_source_event(raw_events, event)
    if raw_events.any? && raw_event.blank?
      return missing_result('source_event_mismatch', 'La ficha de origen contiene otro concierto y no se usaron sus imagenes.')
    end
    if raw_events.empty? && !source_page_context_matches?(html, event)
      return missing_result('source_page_identity_unverified', 'La ficha no permite confirmar que las imagenes pertenezcan al concierto solicitado.')
    end

    structured_candidates = []
    if raw_event
      normalized = source_normalizer.normalize(raw_event)
      structured_candidates.concat(Array(normalized[:image_candidates]).presence || [normalized[:image_url]])
    end
    page_candidates = extract_page_candidates(html, event)
    evidence = {
      match: raw_event ? 'exact_source_event' : 'exact_source_url_without_event_json_ld',
      structured_event_found: raw_event.present?,
      page_candidates_found: page_candidates.size
    }
    result = download_first(
      candidates: structured_candidates + page_candidates,
      resolution_source: 'source_page',
      source_kind: 'source',
      page_url: event[:source_url],
      confidence: 98,
      evidence: evidence,
      limit: MAX_SOURCE_IMAGE_CANDIDATES
    )
    result || missing_result('source_without_working_image', 'La ficha exacta de Songkick no ofrece una imagen valida y descargable.')
  rescue SongkickConcerts::Client::RobotsBlockedError => e
    unavailable_result('source_blocked_by_robots', e.message)
  rescue SongkickConcerts::Client::RequestError => e
    return missing_result('source_event_not_found', e.message) if e.not_found?
    return retryable_result('source_request_error', e.message) if e.retryable?

    unavailable_result('source_request_blocked', e.message)
  end

  def extract_page_candidates(html, event)
    if source_parser.respond_to?(:page_image_candidates)
      source_parser.page_image_candidates(
        html,
        base_url: event[:source_url],
        artist_names: [event[:artist_name], event[:name]].compact,
        source_artist_ids: [event[:source_artist_id]].compact
      )
    else
      source_parser.page_image_urls(html)
    end
  rescue ArgumentError
    source_parser.page_image_candidates(html, base_url: event[:source_url])
  end

  def source_page_context_matches?(html, event)
    document = Nokogiri::HTML(html.to_s)
    page_urls = [
      document.at_css('link[rel~="canonical"][href]')&.[]('href'),
      document.at_css('meta[property="og:url"][content]')&.[]('content')
    ].compact

    expected_id = event[:source_event_id].to_s.presence || event[:source_url].to_s[%r{/concerts/(\d+)}, 1]
    if source_client.respond_to?(:last_response_url) && source_client.last_response_url.present? && expected_id.present?
      final_id = source_client.last_response_url.to_s[%r{/concerts/(\d+)}, 1]
      return false if final_id.present? && final_id != expected_id
    end

    if page_urls.any?
      return page_urls.any? { |url| url.to_s[%r{/concerts/(\d+)}, 1] == expected_id } if expected_id.present?

      expected_path = URI.parse(event[:source_url].to_s).path
      return page_urls.any? { |url| URI.parse(url.to_s).path == expected_path }
    end

    page_text = [document.at_css('title')&.text, document.at_css('h1')&.text].compact.join(' ')
    artist_match = canonical_text(page_text).include?(canonical_text(event[:artist_name].presence || event[:name]))
    year_match = event[:date].blank? || page_text.include?(event[:date].to_date.year.to_s)
    artist_match && year_match
  rescue URI::InvalidURIError, ArgumentError
    false
  end

  def resolve_from_cached_record(record)
    return nil unless record&.resolved? && record.image_url.present?

    download_first(
      candidates: [record.image_url],
      resolution_source: 'artist_cache_url',
      source_kind: 'cache',
      page_url: record.source_page_url,
      confidence: record.confidence,
      evidence: record.evidence.to_h.merge(cache_hit: true, cached_url_reused: true),
      limit: 1,
      identifiers: cache_identifiers(record),
      artist_identity_key: record.identity_key
    )
  end

  def resolve_from_external_sources(event, cached_record)
    return unavailable_result('external_search_disabled', 'La busqueda externa gratuita esta desactivada.') unless external_search_enabled
    return cached_failure_result(cached_record) if cached_record&.fresh? && !cached_record.resolved?

    search = external_search.search(event)
    status = search.respond_to?(:status) ? search.status.to_s : 'not_found'
    identifiers = search.respond_to?(:identifiers) ? search.identifiers.to_h : {}
    providers_checked = search.respond_to?(:provider_attempts) ? search.provider_attempts : []

    if status == 'found' && search.candidate
      candidates = search.respond_to?(:candidates) && search.candidates.present? ? search.candidates : [search.candidate]
      result = download_first(
        candidates: candidates,
        resolution_source: search.candidate.provider.to_s,
        source_kind: 'external',
        page_url: search.candidate.page_url,
        confidence: search.confidence,
        evidence: search.evidence.to_h.merge(provider_attempts: providers_checked),
        limit: MAX_EXTERNAL_IMAGE_CANDIDATES,
        identifiers: identifiers
      )
      return result if result&.recovered?

      return result if result&.retryable?
    end

    result = case status
             when 'ambiguous'
               Result.new(status: 'ambiguous', source_kind: 'external', error_type: search.error_type.presence || 'ambiguous_artist_identity', error_message: search.error_message, evidence: search.evidence, identifiers: identifiers)
             when 'retryable_error'
               retryable_result(search.error_type.presence || 'external_provider_error', search.error_message, evidence: search.evidence, identifiers: identifiers)
             when 'unavailable'
               unavailable_result(search.error_type.presence || 'external_provider_unavailable', search.error_message, evidence: search.evidence, identifiers: identifiers)
             else
               missing_result(search.error_type.presence || 'no_confident_external_image', search.error_message.presence || 'Las fuentes externas estructuradas no ofrecieron una imagen segura.', evidence: search.evidence, identifiers: identifiers)
             end
    persist_failure(event, result, providers_checked)
    result
  rescue StandardError => e
    logger.warn("[concert-cover] external_search_failed artist=#{event[:artist_name].inspect} error=#{e.class}: #{e.message}")
    retryable_result('external_search_error', "#{e.class} - #{e.message}")
  end

  def download_first(candidates:, resolution_source:, source_kind:, page_url:, confidence:, evidence:, limit:, identifiers: {}, artist_identity_key: nil)
    normalized = normalized_candidates(candidates).first(limit)
    return nil if normalized.empty?

    failures = []
    attempts = []
    normalized.each do |candidate|
      url = candidate_url(candidate)
      if placeholder_candidate?(candidate, url)
        attempts << candidate_evidence(candidate, url).merge(status: 'discarded', reason: 'placeholder_or_non_cover_asset')
        logger.debug("[concert-cover] candidate_discarded url=#{url.inspect} reason=placeholder_or_non_cover_asset")
        next
      end

      @image_download_requests_count += 1
      download = downloader.download(url)
      attempt = candidate_evidence(candidate, url).merge(download_evidence(download))
      attempts << attempt
      unless download.ok?
        failures << download
        logger.debug("[concert-cover] candidate_failed url=#{url.inspect} error=#{download.error_type}: #{download.error_message}")
        next
      end

      selected_confidence = [candidate_score(candidate).presence || confidence.to_f, confidence.to_f].min
      return Result.new(
        status: 'recovered',
        download: download,
        resolution_source: resolution_source,
        source_kind: source_kind,
        image_url: download.final_url.presence || url,
        page_url: candidate_page_url(candidate).presence || page_url,
        confidence: selected_confidence,
        evidence: evidence.to_h.merge(selected_candidate: candidate_evidence(candidate, url), candidate_attempts: attempts),
        artist_identity_key: artist_identity_key,
        identifiers: identifiers
      )
    end

    retryable_failure = failures.find { |failure| retryable_download_failure?(failure) }
    failure = retryable_failure || failures.last
    Result.new(
      status: retryable_failure ? 'retryable_error' : 'missing',
      resolution_source: resolution_source,
      source_kind: source_kind,
      page_url: page_url,
      confidence: confidence,
      evidence: evidence.to_h.merge(candidate_urls_checked: normalized.size, candidate_attempts: attempts),
      error_type: failure&.error_type.presence || 'no_usable_image_candidate',
      error_message: failure&.error_message.presence || 'Los candidatos eran placeholders, recursos no relacionados o imagenes tecnicamente invalidas.',
      identifiers: identifiers
    )
  end

  def normalized_candidates(candidates)
    Array(candidates).flatten.compact.uniq { |candidate| candidate_url(candidate) }.select { |candidate| candidate_url(candidate).present? }
  end

  def candidate_url(candidate)
    value = if candidate.respond_to?(:url)
              candidate.url
            elsif candidate.respond_to?(:image_url)
              candidate.image_url
            elsif candidate.is_a?(Hash)
              candidate[:url] || candidate['url'] || candidate[:image_url] || candidate['image_url']
            else
              candidate
            end
    normalize_image_url(value)
  end

  def candidate_page_url(candidate)
    return candidate.page_url if candidate.respond_to?(:page_url)
    return candidate[:page_url] || candidate['page_url'] if candidate.is_a?(Hash)

    nil
  end

  def candidate_score(candidate)
    value = if candidate.respond_to?(:score)
              candidate.score
            elsif candidate.respond_to?(:confidence)
              candidate.confidence
            elsif candidate.is_a?(Hash)
              candidate[:score] || candidate['score'] || candidate[:confidence] || candidate['confidence']
            end
    value.to_f if value.present?
  end

  def candidate_evidence(candidate, url)
    details = if candidate.respond_to?(:evidence)
                candidate.evidence.to_h
              elsif candidate.is_a?(Hash)
                candidate.to_h.except(:url, 'url', :image_url, 'image_url')
              else
                {
                  extraction_source: candidate.respond_to?(:source) ? candidate.source : nil,
                  declared_width: candidate.respond_to?(:width) ? candidate.width : nil,
                  declared_height: candidate.respond_to?(:height) ? candidate.height : nil,
                  document_order: candidate.respond_to?(:order) ? candidate.order : nil
                }.compact
              end
    common = {
      provider: candidate.respond_to?(:provider) ? candidate.provider : nil,
      declared_width: candidate.respond_to?(:width) ? candidate.width : nil,
      declared_height: candidate.respond_to?(:height) ? candidate.height : nil
    }.compact
    details.deep_symbolize_keys.merge(common).merge(url: url, score: candidate_score(candidate)).compact
  end

  def download_evidence(download)
    {
      status: download.ok? ? 'accepted' : 'rejected',
      error_type: download.error_type,
      error_message: download.error_message,
      http_status: download.http_status,
      declared_content_type: download.respond_to?(:declared_content_type) ? download.declared_content_type : nil,
      detected_content_type: download.content_type,
      width: download.respond_to?(:width) ? download.width : nil,
      height: download.respond_to?(:height) ? download.height : nil,
      byte_size: download.respond_to?(:byte_size) ? download.byte_size : download.body.to_s.bytesize
    }.compact
  end

  def placeholder_candidate?(candidate, url)
    return source_parser.placeholder_image_url?(url) if source_parser.respond_to?(:placeholder_image_url?)

    text = [url, candidate_evidence(candidate, url).values].flatten.join(' ').downcase
    text.match?(/default[-_ ]?(?:artist|avatar|image)|placeholder|\b(?:logo|icon|sprite|pixel|spacer)\b/)
  end

  def normalize_image_url(value)
    if defined?(SongkickConcerts::ImageUrlNormalizer)
      SongkickConcerts::ImageUrlNormalizer.normalize(value, base_url: SongkickConcerts::Client::BASE_URL)
    else
      value.to_s.strip.presence
    end
  end

  def finalize_recovered(event, result, persist: true)
    result.artist_identity_key ||= cache_store.identity_key_for(event)
    if persist
      cache_store.store_resolution!(
        event: event,
        result: result,
        providers_checked: Array(result.evidence.to_h[:provider_attempts])
      )
    end
    log_selection(event, result)
    result
  rescue StandardError => e
    logger.warn("[concert-cover-cache] store_resolution_failed artist=#{event[:artist_name].inspect} error=#{e.class}: #{e.message}")
    result
  end

  def finalize_unresolved(event, attempts)
    unresolved = attempts.find(&:ambiguous?) || attempts.find(&:retryable?) || attempts.find(&:unavailable?)
    status = unresolved&.status || 'missing'
    result = Result.new(
      status: status,
      source_kind: unresolved&.source_kind,
      error_type: unresolved&.error_type || attempts.last&.error_type || 'no_cover_found',
      error_message: attempts.filter_map(&:error_message).uniq.join(' | ').presence || 'No se encontro una portada verificable para este concierto.',
      evidence: {
        source_page_attempted: event[:source_url].present?,
        external_search_enabled: external_search_enabled,
        attempts: attempts.map { |attempt| attempt_evidence(attempt) }
      },
      identifiers: unresolved&.identifiers
    )
    logger.public_send(status == 'missing' ? :info : :warn, "[concert-cover] unresolved artist=#{event[:artist_name].inspect} status=#{status} reason=#{result.error_type}")
    result
  end

  def persist_failure(event, result, providers_checked)
    cache_status = if result.ambiguous?
                     'ambiguous'
                   elsif result.status == 'missing'
                     'not_found'
                   else
                     result.status
                   end
    cache_store.store_failure!(
      event: event,
      status: cache_status,
      evidence: result.evidence,
      failure_reason: result.error_message,
      providers_checked: providers_checked,
      identifiers: result.identifiers.to_h
    )
  rescue StandardError => e
    logger.warn("[concert-cover-cache] store_failure_failed artist=#{event[:artist_name].inspect} error=#{e.class}: #{e.message}")
  end

  def cached_failure_result(record)
    status = record.status == 'not_found' ? 'missing' : record.status
    Result.new(
      status: status,
      source_kind: 'cache',
      error_type: "cached_#{record.status}",
      error_message: record.failure_reason,
      evidence: record.evidence.to_h.merge(cache_hit: true, retry_after: record.retry_after),
      artist_identity_key: record.identity_key,
      identifiers: cache_identifiers(record)
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
    metadata = venue.respond_to?(:festival_metadata) ? venue.festival_metadata.to_h.deep_symbolize_keys : {}
    imported = venue.concert_import_items.recent_first.first&.normalized_payload.to_h.deep_symbolize_keys
    details = Array(metadata[:performer_details]).presence || Array(imported&.dig(:performer_details))
    primary = details.first.to_h.deep_symbolize_keys
    {
      name: venue.name,
      artist_name: primary[:name].presence || Array(metadata[:performers]).first.presence || venue.name,
      source_artist_id: primary[:source_artist_id].presence || source_artist_id_from_urls(venue_source_image_urls(venue)),
      songkick_artist_id: primary[:source_artist_id].presence || source_artist_id_from_urls(venue_source_image_urls(venue)),
      artist_source_url: primary[:same_as],
      artist_official_url: primary[:official_url],
      artist_official_urls: Array(primary[:same_as]).reject { |url| url.to_s.include?('songkick.com/artists/') },
      genres: Array(primary[:genres]).presence || Array(metadata[:genres]),
      date: venue.event_start_at.presence || venue.festival_start_date,
      city: venue.city,
      venue_name: venue.respond_to?(:festival_venue_name) ? venue.festival_venue_name : nil,
      source_url: venue.respond_to?(:external_source_url) ? venue.external_source_url : nil,
      source_event_id: venue.respond_to?(:external_source_id) ? venue.external_source_id : nil
    }
  end

  def event_from_normalized(normalized)
    primary = Array(normalized[:performer_details]).first.to_h.deep_symbolize_keys
    {
      name: normalized[:name],
      artist_name: normalized[:artist_name].presence || primary[:name].presence || Array(normalized[:performers]).first.presence || normalized[:name],
      source_artist_id: normalized[:source_artist_id].presence || primary[:source_artist_id],
      songkick_artist_id: normalized[:source_artist_id].presence || primary[:source_artist_id],
      artist_source_url: primary[:same_as],
      genres: Array(primary[:genres]).presence || Array(normalized[:genres]),
      country_code: primary[:country_code],
      artist_country: primary[:country_code],
      official_url: primary[:official_url],
      artist_official_url: primary[:official_url],
      artist_official_urls: Array(primary[:same_as]).reject { |url| url.to_s.include?('songkick.com/artists/') },
      date: normalized[:start_at].presence || normalized[:start_date],
      city: normalized[:city],
      venue_name: normalized[:venue_name],
      source_url: normalized[:source_url],
      source_event_id: normalized[:source_event_id]
    }
  end

  def venue_source_image_urls(venue)
    existing_urls = venue.venue_images.to_a.map(&:url)
    imported_urls = venue.concert_import_items.where.not(image_url: [nil, '']).recent_first.limit(12).pluck(:image_url)
    (existing_urls + imported_urls).compact.uniq
  end

  def source_artist_id_from_urls(urls)
    Array(urls).filter_map { |url| url.to_s[%r{/artists/(\d+)}, 1] }.first
  end

  def cache_identifiers(record)
    { musicbrainz_id: record.musicbrainz_id, wikidata_id: record.wikidata_id }.compact
  end

  def canonical_text(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
  end

  def missing_result(error_type, message, evidence: nil, identifiers: nil)
    Result.new(status: 'missing', error_type: error_type, error_message: message, evidence: evidence, identifiers: identifiers)
  end

  def retryable_result(error_type, message, evidence: nil, identifiers: nil)
    Result.new(status: 'retryable_error', error_type: error_type, error_message: message, evidence: evidence, identifiers: identifiers)
  end

  def unavailable_result(error_type, message, evidence: nil, identifiers: nil)
    Result.new(status: 'unavailable', error_type: error_type, error_message: message, evidence: evidence, identifiers: identifiers)
  end

  def retryable_download_failure?(failure)
    return true if %w[timeout network_error unknown_error empty_response].include?(failure.error_type.to_s)

    failure.http_status.to_i == 429 || failure.http_status.to_i >= 500
  end

  def attempt_evidence(attempt)
    {
      status: attempt.status,
      source: attempt.resolution_source,
      source_kind: attempt.source_kind,
      error_type: attempt.error_type,
      error_message: attempt.error_message,
      evidence: attempt.evidence
    }.compact
  end

  def log_selection(event, result)
    logger.info(
      "[concert-cover] selected artist=#{event[:artist_name].inspect} source=#{result.resolution_source} " \
      "confidence=#{result.confidence} dimensions=#{result.download.respond_to?(:width) ? "#{result.download.width}x#{result.download.height}" : 'unknown'}"
    )
  end
end
