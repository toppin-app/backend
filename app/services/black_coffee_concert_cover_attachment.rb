require 'stringio'

class BlackCoffeeConcertCoverAttachment
  SOURCE_PREFIX = 'concert_cover'.freeze
  MAX_STORED_BYTES = 25.megabytes

  class PersistenceError < StandardError; end

  def self.attach!(venue:, download:, resolution_source:, source_url:, provenance: {})
    new(
      venue: venue,
      download: download,
      resolution_source: resolution_source,
      source_url: source_url,
      provenance: provenance
    ).attach!
  end

  def self.persisted_binary(venue:, venue_image:)
    return unless venue&.id && venue_image.is_a?(VenueImage) && venue_image.id

    stored = VenueImage.uploaded_sources.find_by(id: venue_image.id, venue_id: venue.id)
    return unless stored&.persisted? && stored.uploaded_image?

    file = stored.image.file
    return unless file

    exists =
      if file.respond_to?(:exists?)
        file.exists?
      elsif file.respond_to?(:path)
        File.file?(file.path.to_s)
      else
        false
      end

    exists ? stored : nil
  rescue StandardError => e
    Rails.logger.warn(
      "[concert-cover-attachment] storage_verification_failed venue_id=#{venue&.id.inspect} " \
      "venue_image_id=#{venue_image&.id.inspect} error=#{e.class}: #{e.message}"
    )
    nil
  end

  def self.verify_persisted!(venue:, venue_image:)
    usable_persisted_binary(venue: venue, venue_image: venue_image) || raise(
      PersistenceError,
      'La portada no quedo persistida como un binario visualmente util en el almacenamiento interno.'
    )
  end

  def self.usable_persisted_binary(venue:, venue_image:, inspector: nil)
    stored = persisted_binary(venue: venue, venue_image: venue_image)
    return unless stored

    file = stored.image.file
    return if file.respond_to?(:size) && file.size.to_i > MAX_STORED_BYTES

    body = stored.image.read.to_s.b
    return if body.empty? || body.bytesize > MAX_STORED_BYTES

    inspection = (inspector || BlackCoffeeImageInspector.new(validate_visual_content: true)).call(
      body,
      declared_content_type: file.respond_to?(:content_type) ? file.content_type : nil
    )
    unless inspection.ok?
      Rails.logger.info(
        "[concert-cover-attachment] stored_binary_unusable venue_id=#{venue.id.inspect} " \
        "venue_image_id=#{stored.id.inspect} error=#{inspection.error_type}"
      )
      return
    end

    stored
  rescue StandardError => e
    Rails.logger.warn(
      "[concert-cover-attachment] stored_binary_inspection_failed venue_id=#{venue&.id.inspect} " \
      "venue_image_id=#{venue_image&.id.inspect} error=#{e.class}: #{e.message}"
    )
    nil
  end

  def initialize(venue:, download:, resolution_source:, source_url:, provenance: {})
    @venue = venue
    @download = download
    @resolution_source = resolution_source
    @source_url = source_url
    @provenance = provenance
  end

  def attach!
    raise ArgumentError, 'La descarga de portada no es valida.' unless download&.ok?

    VenueImage.transaction do
      image = reusable_cover || venue.venue_images.create!(
        url: source_url,
        source: source_label,
        position: next_available_position
      )
      original_position = image.position
      image.image = uploaded_io(image)
      image.url = nil
      image.source = source_label
      image.author_attributions = provenance_payload
      image.position = original_position
      image.save!
      self.class.verify_persisted!(venue: venue, venue_image: image)
    end
  end

  private

  attr_reader :venue, :download, :resolution_source, :source_url, :provenance

  def reusable_cover
    venue.venue_images.to_a.sort_by { |image| [image.position.to_i, image.id.to_i] }.find do |image|
      self.class.usable_persisted_binary(venue: venue, venue_image: image).nil?
    end
  end

  def next_available_position
    (venue.venue_images.to_a.map { |image| image.position.to_i }.max || -1) + 1
  end

  def uploaded_io(image)
    io = StringIO.new(download.body.to_s.b)
    extension = download.extension.presence || 'jpg'
    content_type = download.content_type.presence || 'image/jpeg'
    filename = "black_coffee_concert_cover_#{venue.id}_#{image.id}.#{extension}"
    io.define_singleton_method(:original_filename) { filename }
    io.define_singleton_method(:content_type) { content_type }
    io
  end

  def source_label
    "#{SOURCE_PREFIX}_#{resolution_source}".first(255)
  end

  def provenance_payload
    provenance.to_h.deep_stringify_keys.merge(
      'stored_as_binary_at' => Time.current.iso8601
    )
  end
end
