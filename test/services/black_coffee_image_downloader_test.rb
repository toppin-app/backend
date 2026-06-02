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
    net_http_start = lambda do |_host, _port, **_options, &_block|
      raise 'network should not be called'
    end

    Net::HTTP.stub(:start, net_http_start) do
      result = BlackCoffeeImageDownloader.new.download(url)

      assert_not result.ok?
      assert_equal 'temporary_google_photo_uri', result.error_type
    end
  end

  test 'returns a successful result from streamed image responses' do
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
      result = BlackCoffeeImageDownloader.new.download('https://cdn.toppin.test/image.jpg')

      assert result.ok?
      assert_equal 'hello-image', result.body
      assert_equal 'image/jpeg', result.content_type
      assert_equal 'jpg', result.extension
      assert_equal 200, result.http_status
    end
  end

  test 'rejects non image content types' do
    response = FakeStreamingResponse.new('200', { 'content-type' => 'text/html' }, ['not an image'])
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |_request, &block|
      block.call(response)
      response
    end
    net_http_start = lambda do |_host, _port, **_options, &block|
      block.call(fake_http)
    end

    Net::HTTP.stub(:start, net_http_start) do
      result = BlackCoffeeImageDownloader.new.download('https://cdn.toppin.test/page.html')

      assert_not result.ok?
      assert_equal 'not_image', result.error_type
    end
  end
end
