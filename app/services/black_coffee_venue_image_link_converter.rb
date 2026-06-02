require 'stringio'

class BlackCoffeeVenueImageLinkConverter
  INTERNALIZED_SOURCE = 'internalized_link'.freeze

  Result = Struct.new(:venue_id, :converted_count, :skipped_count, :failed_count, :items, keyword_init: true) do
    def success?
      failed_count.to_i.zero?
    end

    def converted?
      converted_count.to_i.positive?
    end

    def failed_items
      items.select { |item| item.status == 'failed' }
    end
  end

  ItemResult = Struct.new(
    :venue_image_id,
    :status,
    :source_url,
    :file_size,
    :content_type,
    :http_status,
    :error_type,
    :error_message,
    keyword_init: true
  )

  def self.convert!(venue:, downloader: nil, limit: nil)
    new(venue: venue, downloader: downloader, limit: limit).convert!
  end

  def initialize(venue:, downloader: nil, limit: nil)
    @venue = venue
    @downloader = downloader || self.class.default_downloader
    @limit = limit.to_i.positive? ? limit.to_i : nil
  end

  def convert!
    items = candidate_images.map { |image| convert_image(image) }

    Result.new(
      venue_id: venue.id,
      converted_count: items.count { |item| item.status == 'converted' },
      skipped_count: items.count { |item| item.status == 'skipped' },
      failed_count: items.count { |item| item.status == 'failed' },
      items: items
    )
  end

  private

  attr_reader :venue, :downloader, :limit

  def self.default_downloader
    BlackCoffeeImageDownloader.new
  end

  def candidate_images
    images = venue.venue_images.to_a.sort_by { |image| [image.position.to_i, image.id.to_i] }
    images = images.first(limit) if limit
    images
  end

  def convert_image(image)
    return skipped_item(image, 'not_external_link', 'La imagen ya es interna o no tiene link externo.') unless image.external_image?

    source_url = image.url.to_s.strip
    download = downloader.download(source_url)
    return failed_item(image, source_url, download) unless download.ok?

    attach_download!(image, download)

    ItemResult.new(
      venue_image_id: image.id,
      status: 'converted',
      source_url: source_url,
      file_size: download.body.bytesize,
      content_type: download.content_type,
      http_status: download.http_status
    )
  rescue ActiveRecord::ActiveRecordError, CarrierWave::IntegrityError, CarrierWave::ProcessingError => e
    failed_item_from_error(image, source_url, 'save_error', e.message)
  end

  def attach_download!(image, download)
    uploaded_io = upload_io_for(image, download)

    image.image = uploaded_io
    image.url = nil
    image.source = INTERNALIZED_SOURCE if image.has_attribute?(:source)
    image.save!
  end

  def upload_io_for(image, download)
    body = download.body.to_s.b
    io = StringIO.new(body)
    extension = download.extension.presence || 'jpg'
    content_type = download.content_type.presence || 'image/jpeg'
    filename = "black_coffee_venue_image_#{image.id}.#{extension}"

    io.define_singleton_method(:original_filename) { filename }
    io.define_singleton_method(:content_type) { content_type }
    io
  end

  def skipped_item(image, error_type, message)
    ItemResult.new(
      venue_image_id: image.id,
      status: 'skipped',
      source_url: image.respond_to?(:url) ? image.url : nil,
      error_type: error_type,
      error_message: message
    )
  end

  def failed_item(image, source_url, download)
    ItemResult.new(
      venue_image_id: image.id,
      status: 'failed',
      source_url: source_url,
      http_status: download.http_status,
      error_type: download.error_type,
      error_message: download.error_message
    )
  end

  def failed_item_from_error(image, source_url, error_type, message)
    ItemResult.new(
      venue_image_id: image.id,
      status: 'failed',
      source_url: source_url,
      error_type: error_type,
      error_message: message
    )
  end
end
