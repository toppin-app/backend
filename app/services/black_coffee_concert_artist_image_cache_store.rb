require 'digest'

class BlackCoffeeConcertArtistImageCacheStore
  POSITIVE_TTL = 180.days
  NOT_FOUND_TTL = 7.days
  AMBIGUOUS_TTL = 30.days
  RETRYABLE_TTL = 15.minutes
  UNAVAILABLE_TTL = 1.day

  CacheLookup = Struct.new(:record, :download, keyword_init: true) do
    def reusable?
      download&.ok?
    end
  end

  def initialize(scope: BlackCoffeeConcertArtistImageCache.all, inspector: nil, logger: Rails.logger, available: nil)
    @scope = scope
    @inspector = inspector
    @logger = logger
    @available = available
  end

  def identity_key_for(event)
    source_artist_id = event[:source_artist_id].to_s.strip
    return "songkick:#{source_artist_id}" if source_artist_id.present?

    musicbrainz_id = event[:musicbrainz_id].to_s.strip.downcase
    return "musicbrainz:#{musicbrainz_id}" if musicbrainz_id.present?

    wikidata_id = event[:wikidata_id].to_s.strip.upcase
    return "wikidata:#{wikidata_id}" if wikidata_id.present?

    name = canonical_text(event[:artist_name].presence || event[:name])
    return nil if name.blank?

    qualifiers = Array(event[:genres]).map { |genre| canonical_text(genre) }.reject(&:blank?).sort.first(5)
    "name:#{Digest::SHA256.hexdigest(([name] + qualifiers).join('|'))}"
  end

  def lookup(event)
    return nil unless available?

    key = identity_key_for(event)
    return nil if key.blank?

    record = scope.find_by(identity_key: key)
    return nil unless record&.fresh?
    # A name-only key is useful for short-lived negative caching, but it is
    # never sufficient to reuse a positive image across concerts.
    return nil if record.resolved? && key.start_with?('name:')

    download = record.reusable_binary? ? download_from(record.venue_image, record) : nil
    CacheLookup.new(record: record, download: download)
  rescue StandardError => e
    logger.warn("[concert-cover-cache] lookup_failed key=#{key.inspect} error=#{e.class}: #{e.message}")
    nil
  end

  def store_resolution!(event:, result:, providers_checked: nil)
    return nil unless available?

    key = identity_key_for(event)
    return nil if key.blank?

    identifiers = result.respond_to?(:identifiers) ? result.identifiers.to_h.symbolize_keys : {}
    attributes = base_attributes(event).merge(
      status: 'resolved',
      provider: result.resolution_source,
      image_url: result.image_url,
      source_page_url: result.page_url,
      confidence: result.confidence,
      image_width: result.download&.respond_to?(:width) ? result.download.width : nil,
      image_height: result.download&.respond_to?(:height) ? result.download.height : nil,
      image_bytes: result.download&.body.to_s.bytesize,
      image_content_type: result.download&.content_type,
      image_sha256: result.download&.respond_to?(:sha256) ? result.download.sha256 : nil,
      providers_checked: providers_checked,
      evidence: result.evidence,
      failure_reason: nil,
      searched_at: Time.current,
      retry_after: nil,
      expires_at: Time.current + POSITIVE_TTL
    )
    attributes[:musicbrainz_id] = identifiers[:musicbrainz_id] if identifiers[:musicbrainz_id].present?
    attributes[:wikidata_id] = identifiers[:wikidata_id] if identifiers[:wikidata_id].present?
    upsert_record(key, attributes)
  end

  def store_failure!(event:, status:, evidence:, failure_reason:, providers_checked: nil, identifiers: {})
    return nil unless available?

    key = identity_key_for(event)
    return nil if key.blank?

    ttl = ttl_for(status)
    attributes = base_attributes(event).merge(
      status: status,
      musicbrainz_id: identifiers[:musicbrainz_id],
      wikidata_id: identifiers[:wikidata_id],
      provider: nil,
      image_url: nil,
      source_page_url: nil,
      confidence: nil,
      providers_checked: providers_checked,
      evidence: evidence,
      failure_reason: failure_reason,
      searched_at: Time.current,
      retry_after: Time.current + ttl,
      expires_at: Time.current + ttl
    )
    upsert_record(key, attributes)
  end

  def link_attachment!(identity_key:, venue_image:)
    return unless available?
    return if identity_key.blank? || venue_image.blank?

    scope.find_by(identity_key: identity_key)&.update!(venue_image: venue_image)
  rescue StandardError => e
    logger.warn("[concert-cover-cache] attachment_link_failed key=#{identity_key.inspect} error=#{e.class}: #{e.message}")
  end

  private

  attr_reader :scope, :logger

  def available?
    return @available unless @available.nil?

    BlackCoffeeConcertArtistImageCache.table_exists?
  rescue ActiveRecord::ActiveRecordError
    false
  end

  def inspector
    @inspector ||= BlackCoffeeImageInspector.new(validate_visual_content: true)
  end

  def download_from(venue_image, record)
    body = read_uploader(venue_image.image)
    inspection = inspector.call(body, declared_content_type: record.image_content_type)
    return nil unless inspection.ok?

    BlackCoffeeImageDownloader::DownloadResult.new(
      ok?: true,
      body: body,
      content_type: inspection.content_type,
      extension: inspection.extension,
      http_status: 200,
      final_url: venue_image.image.url,
      width: inspection.width,
      height: inspection.height,
      byte_size: body.bytesize,
      sha256: inspection.sha256,
      declared_content_type: record.image_content_type
    )
  end

  def read_uploader(uploader)
    file = uploader.file
    return file.read if file.respond_to?(:read)
    return File.binread(file.path) if file.respond_to?(:path) && file.path.present?
    return uploader.read if uploader.respond_to?(:read)

    raise IOError, 'La portada cacheada no se puede leer desde el almacenamiento.'
  end

  def upsert_record(key, attributes)
    record = scope.find_or_initialize_by(identity_key: key)
    record.assign_attributes(attributes)
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    retry_record = scope.find_by!(identity_key: key)
    retry_record.update!(attributes)
    retry_record
  end

  def base_attributes(event)
    artist_name = event[:artist_name].presence || event[:name].to_s
    {
      artist_name: artist_name,
      canonical_name: canonical_text(artist_name),
      source_artist_id: event[:source_artist_id]
    }
  end

  def ttl_for(status)
    {
      'not_found' => NOT_FOUND_TTL,
      'ambiguous' => AMBIGUOUS_TTL,
      'retryable_error' => RETRYABLE_TTL,
      'unavailable' => UNAVAILABLE_TTL
    }.fetch(status.to_s, NOT_FOUND_TTL)
  end

  def canonical_text(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
  end
end
