require 'test_helper'
require 'zip'

class BlackCoffeeWorkingImageExporterTest < ActiveSupport::TestCase
  FakeVenue = Struct.new(:name)
  FakeStreamingResponse = Struct.new(:code, :headers, :chunks) do
    def [](key)
      headers.to_h[key.to_s.downcase]
    end

    def read_body
      chunks.each { |chunk| yield chunk }
    end
  end

  FakeImage = Struct.new(:id, :venue_id, :position, :url, :venue, keyword_init: true) do
    def temporary_google_place_photo_url?
      VenueImage.temporary_google_place_photo_url?(url)
    end

    def public_url(base_url: nil)
      temporary_google_place_photo_url? ? nil : url
    end

    def uploaded_image?
      false
    end
  end

  class FakeDownloader
    attr_reader :requested_urls

    def initialize
      @requested_urls = []
    end

    def download(url)
      requested_urls << url
      return failure('http_error', 'La imagen responde HTTP 404.', 404) if url.include?('broken')

      BlackCoffeeWorkingImageExporter::DownloadResult.new(
        ok?: true,
        body: "image-bytes-#{requested_urls.size}",
        content_type: 'image/jpeg',
        extension: 'jpg',
        http_status: 200
      )
    end

    private

    def failure(error_type, message, http_status)
      BlackCoffeeWorkingImageExporter::DownloadResult.new(
        ok?: false,
        error_type: error_type,
        error_message: message,
        http_status: http_status
      )
    end
  end

  test 'exports only working non temporary images and includes a manifest' do
    downloader = FakeDownloader.new
    images = [
      fake_image(1, 'https://lh3.googleusercontent.com/place-photos/AJRVUZExample=s4800-w1200'),
      fake_image(2, 'https://cdn.toppin.test/broken.jpg'),
      fake_image(3, 'https://cdn.toppin.test/ok.jpg')
    ]

    result = BlackCoffeeWorkingImageExporter.new(
      limit: 10,
      base_url: 'https://admin.toppin.test',
      downloader: downloader,
      image_scope: images
    ).export

    zip_entries = entries_for(result.zip_data)
    manifest = JSON.parse(zip_entries.fetch('manifest.json'))

    assert_equal ['https://cdn.toppin.test/broken.jpg', 'https://cdn.toppin.test/ok.jpg'], downloader.requested_urls
    assert_equal 1, manifest['included_count']
    assert_equal 2, manifest['skipped_count']
    assert_equal 'temporary_google_photo_uri', manifest['skipped'].first['error_type']
    assert zip_entries.keys.any? { |name| name.end_with?('.jpg') }
  end

  test 'real downloader returns a download result from Net HTTP streaming responses' do
    response = FakeStreamingResponse.new('200', { 'content-type' => 'image/jpeg' }, ['hello-', 'image'])
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |_request, &block|
      block.call(response)
      response
    end
    net_http_start = lambda do |_host, _port, use_ssl:, open_timeout:, read_timeout:, &block|
      block.call(fake_http)
    end

    Net::HTTP.stub(:start, net_http_start) do
      result = BlackCoffeeWorkingImageExporter::ImageDownloader.new.download('https://cdn.toppin.test/image.jpg')

      assert result.ok?
      assert_equal 'hello-image', result.body
      assert_equal 'image/jpeg', result.content_type
      assert_equal 200, result.http_status
    end
  end

  test 'requested limit is clamped to the maximum allowed batch size' do
    result = BlackCoffeeWorkingImageExporter.new(
      limit: 2_500,
      base_url: 'https://admin.toppin.test',
      image_scope: []
    ).export

    assert_equal 1_000, result.manifest[:requested_limit]
  end

  private

  def fake_image(id, url)
    FakeImage.new(
      id: id,
      venue_id: "ven_#{id}",
      position: id,
      url: url,
      venue: FakeVenue.new("Local #{id}")
    )
  end

  def entries_for(zip_data)
    entries = {}
    Zip::File.open_buffer(StringIO.new(zip_data)) do |zip|
      zip.each do |entry|
        entries[entry.name] = entry.get_input_stream.read
      end
    end
    entries
  end
end
