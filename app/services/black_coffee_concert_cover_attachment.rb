require 'stringio'

class BlackCoffeeConcertCoverAttachment
  SOURCE_PREFIX = 'concert_cover'.freeze

  def self.attach!(venue:, download:, resolution_source:, source_url:, provenance: {})
    new(
      venue: venue,
      download: download,
      resolution_source: resolution_source,
      source_url: source_url,
      provenance: provenance
    ).attach!
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
        position: 0
      )
      image.image = uploaded_io(image)
      image.url = nil
      image.source = source_label
      image.author_attributions = provenance_payload
      image.position = 0
      image.save!
      image
    end
  end

  private

  attr_reader :venue, :download, :resolution_source, :source_url, :provenance

  def reusable_cover
    venue.venue_images.to_a.sort_by { |image| [image.position.to_i, image.id.to_i] }.find do |image|
      !image.uploaded_image?
    end
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
