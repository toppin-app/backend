require 'test_helper'

class BlackCoffeeImageDownloaderTest < ActiveSupport::TestCase
  FakeStreamingResponse = Struct.new(:code, :headers, :chunks) do
    def [](key)
      headers.to_h[key.to_s.downcase]
    end

    def read_body
      chunks.each { |chunk| yield chunk }
    end
  end

  test 'skips temporary Google place photo URLs without network requests' do
    url = 'https://lh3.googleusercontent.com/place-photos/AJRVUZExample=s4800-w1200'
    http_factory = lambda do |_uri, _address|
      raise 'network should not be called'
    end
    result = BlackCoffeeImageDownloader.new(http_factory: http_factory).download(url)

    assert_not result.ok?
    assert_equal 'temporary_google_photo_uri', result.error_type
  end

  test 'returns a successful result from streamed image responses' do
    response = FakeStreamingResponse.new('200', { 'content-type' => 'image/jpeg' }, ['hello-', 'image'])
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |_request, &block|
      block.call(response)
      response
    end
    fake_http.define_singleton_method(:start) { |&block| block.call(fake_http) }
    connected_address = nil
    result = public_downloader(fake_http, on_connect: ->(address) { connected_address = address })
             .download('https://cdn.toppin.test/image.jpg')

    assert result.ok?
    assert_equal 'hello-image', result.body
    assert_equal 'image/jpeg', result.content_type
    assert_equal 'jpg', result.extension
    assert_equal 200, result.http_status
    assert_equal '93.184.216.34', connected_address
  end

  test 'rejects non image content types' do
    response = FakeStreamingResponse.new('200', { 'content-type' => 'text/html' }, ['not an image'])
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |_request, &block|
      block.call(response)
      response
    end
    fake_http.define_singleton_method(:start) { |&block| block.call(fake_http) }
    result = public_downloader(fake_http).download('https://cdn.toppin.test/page.html')

    assert_not result.ok?
    assert_equal 'not_image', result.error_type
  end

  test 'blocks private destinations before making a request' do
    downloader = BlackCoffeeImageDownloader.new(address_resolver: ->(_host) { ['127.0.0.1'] })

    result = downloader.download('https://images.example.com/cover.jpg')

    assert_not result.ok?
    assert_equal 'blocked_destination', result.error_type
  end

  private

  def public_downloader(fake_http, on_connect: nil)
    BlackCoffeeImageDownloader.new(
      address_resolver: ->(_host) { ['93.184.216.34'] },
      http_factory: lambda do |_uri, address|
        on_connect&.call(address)
        fake_http
      end
    )
  end
end
