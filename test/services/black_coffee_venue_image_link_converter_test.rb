require 'test_helper'

class BlackCoffeeVenueImageLinkConverterTest < ActiveSupport::TestCase
  FakeVenue = Struct.new(:id, :venue_images)

  class FakeImage
    attr_accessor :id, :venue_id, :position, :url, :source, :assigned_image

    def initialize(id:, url:, position: 0, source: 'google_places')
      @id = id
      @venue_id = 'ven_test'
      @position = position
      @url = url
      @source = source
      @saved = false
    end

    def external_image?
      url.present?
    end

    def has_attribute?(attribute)
      attribute.to_s == 'source'
    end

    def image=(value)
      @assigned_image = value
    end

    def save!
      @saved = true
    end

    def saved?
      @saved
    end
  end

  class FakeDownloader
    attr_reader :requested_urls

    def initialize(success_urls: [])
      @success_urls = success_urls
      @requested_urls = []
    end

    def download(url)
      requested_urls << url
      return failure('http_error', 'La imagen responde HTTP 403.', 403) unless success_urls.include?(url)

      BlackCoffeeImageDownloader::DownloadResult.new(
        ok?: true,
        body: 'image-bytes',
        content_type: 'image/jpeg',
        extension: 'jpg',
        http_status: 200
      )
    end

    private

    attr_reader :success_urls

    def failure(error_type, message, http_status)
      BlackCoffeeImageDownloader::DownloadResult.new(
        ok?: false,
        error_type: error_type,
        error_message: message,
        http_status: http_status
      )
    end
  end

  test 'converts external image links into uploaded image files' do
    image = FakeImage.new(id: 12, url: 'https://cdn.toppin.test/place.jpg')
    downloader = FakeDownloader.new(success_urls: [image.url])
    venue = FakeVenue.new('ven_test', [image])

    result = BlackCoffeeVenueImageLinkConverter.convert!(venue: venue, downloader: downloader)

    assert_equal 1, result.converted_count
    assert_equal 0, result.failed_count
    assert_nil image.url
    assert image.saved?
    assert_equal 'internalized_link', image.source
    assert_equal 'image/jpeg', image.assigned_image.content_type
    assert_equal 'black_coffee_venue_image_12.jpg', image.assigned_image.original_filename
    assert_equal ['https://cdn.toppin.test/place.jpg'], downloader.requested_urls
  end

  test 'keeps the original link when download fails' do
    image = FakeImage.new(id: 13, url: 'https://cdn.toppin.test/expired.jpg')
    downloader = FakeDownloader.new(success_urls: [])
    venue = FakeVenue.new('ven_test', [image])

    result = BlackCoffeeVenueImageLinkConverter.convert!(venue: venue, downloader: downloader)

    assert_equal 0, result.converted_count
    assert_equal 1, result.failed_count
    assert_equal 'https://cdn.toppin.test/expired.jpg', image.url
    assert_not image.saved?
    assert_nil image.assigned_image
    assert_equal 'http_error', result.failed_items.first.error_type
  end

  test 'skips images that are already internal' do
    image = FakeImage.new(id: 14, url: nil)
    downloader = FakeDownloader.new(success_urls: [])
    venue = FakeVenue.new('ven_test', [image])

    result = BlackCoffeeVenueImageLinkConverter.convert!(venue: venue, downloader: downloader)

    assert_equal 0, result.converted_count
    assert_equal 1, result.skipped_count
    assert_empty downloader.requested_urls
  end
end
