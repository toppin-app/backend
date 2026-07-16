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

  class FakeHttp
    def initialize(response, requests)
      @response = response
      @requests = requests
    end

    def start
      yield self
    end

    def request(request)
      @requests << request
      yield @response if block_given?
      @response
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

  test 'returns dimensions and hash from a streamed image response' do
    body = jpeg_bytes(width: 800, height: 600)
    response = response_with(code: 200, content_type: 'image/jpeg', chunks: split_chunks(body))
    requests = []
    addresses = []
    downloader = public_downloader(
      [response],
      requests: requests,
      addresses: addresses
    )

    result = downloader.download('https://cdn.toppin.test/image.jpg')

    assert result.ok?
    assert_equal body, result.body
    assert_equal 'image/jpeg', result.content_type
    assert_equal 'jpg', result.extension
    assert_equal 800, result.width
    assert_equal 600, result.height
    assert_equal 480_000, result.pixels
    assert_equal body.bytesize, result.byte_size
    assert_equal Digest::SHA256.hexdigest(body), result.sha256
    assert_equal 'image/jpeg', result.declared_content_type
    assert_equal 200, result.http_status
    assert_equal ['93.184.216.34'], addresses
    assert_equal BlackCoffeeImageDownloader::DEFAULT_ACCEPT, requests.first['Accept']
  end

  test 'accepts a jpeg served as application octet stream based on its bytes' do
    body = jpeg_bytes(width: 1_200, height: 800)
    response = response_with(
      code: 200,
      content_type: 'application/octet-stream',
      chunks: [body]
    )

    result = public_downloader([response]).download('https://cdn.toppin.test/binary-image')

    assert result.ok?
    assert_equal 'image/jpeg', result.content_type
    assert_equal 'jpg', result.extension
    assert_equal 1_200, result.width
    assert_equal 800, result.height
    assert_equal 'application/octet-stream', result.declared_content_type
  end

  test 'rejects html even when the response claims to be an image' do
    body = '<!doctype html><html><body>not an image</body></html>'
    response = response_with(code: 200, content_type: 'image/jpeg', chunks: [body])

    result = public_downloader([response]).download('https://cdn.toppin.test/not-really.jpg')

    assert_not result.ok?
    assert_equal 'not_image', result.error_type
    assert_equal Digest::SHA256.hexdigest(body), result.sha256
  end

  test 'rejects html served as an octet stream based on its bytes' do
    body = '<html><body>binary-looking response</body></html>'
    response = response_with(
      code: 200,
      content_type: 'application/octet-stream',
      chunks: [body]
    )

    result = public_downloader([response]).download('https://cdn.toppin.test/response.bin')

    assert_not result.ok?
    assert_equal 'not_image', result.error_type
    assert_equal 'application/octet-stream', result.declared_content_type
  end

  test 'follows a relative redirect and inspects the final response' do
    body = jpeg_bytes(width: 900, height: 600)
    redirect = FakeStreamingResponse.new(
      '302',
      { 'location' => '/final/artist.jpg', 'content-type' => 'text/html' },
      []
    )
    image = response_with(code: 200, content_type: 'binary/octet-stream', chunks: [body])
    requested_uris = []
    requests = []
    downloader = public_downloader(
      [redirect, image],
      requested_uris: requested_uris,
      requests: requests
    )

    result = downloader.download('https://cdn.toppin.test/original/artist')

    assert result.ok?
    assert_equal 'https://cdn.toppin.test/final/artist.jpg', result.final_url
    assert_equal [
      'https://cdn.toppin.test/original/artist',
      'https://cdn.toppin.test/final/artist.jpg'
    ], requested_uris
    assert_equal 2, requests.size
  end

  test 'rejects a technically valid image below configured dimensions' do
    body = jpeg_bytes(width: 64, height: 64)
    response = response_with(code: 200, content_type: 'image/jpeg', chunks: [body])
    downloader = public_downloader(
      [response],
      min_width: 100,
      min_height: 100,
      min_pixels: 10_000
    )

    result = downloader.download('https://cdn.toppin.test/placeholder.jpg')

    assert_not result.ok?
    assert_equal 'image_too_small', result.error_type
    assert_equal 64, result.width
    assert_equal 64, result.height
    assert_equal 4_096, result.pixels
    assert_equal Digest::SHA256.hexdigest(body), result.sha256
  end

  test 'returns provider rate limiting as an http error with status 429' do
    response = response_with(
      code: 429,
      content_type: 'application/json',
      chunks: ['{"error":"rate limited"}']
    )

    result = public_downloader([response]).download('https://provider.toppin.test/image.jpg')

    assert_not result.ok?
    assert_equal 'http_error', result.error_type
    assert_equal 429, result.http_status
    assert_match(/HTTP 429/, result.error_message)
  end

  test 'blocks private destinations before making a request' do
    downloader = BlackCoffeeImageDownloader.new(address_resolver: ->(_host) { ['127.0.0.1'] })

    result = downloader.download('https://images.example.com/cover.jpg')

    assert_not result.ok?
    assert_equal 'blocked_destination', result.error_type
  end

  test 'blocks private IPv4 destinations represented as IPv4-mapped IPv6' do
    downloader = BlackCoffeeImageDownloader.new(address_resolver: ->(_host) { ['::ffff:127.0.0.1'] })

    result = downloader.download('https://images.example.com/cover.jpg')

    assert_not result.ok?
    assert_equal 'blocked_destination', result.error_type
  end

  private

  def response_with(code:, content_type:, chunks:)
    FakeStreamingResponse.new(
      code.to_s,
      { 'content-type' => content_type },
      chunks
    )
  end

  def public_downloader(responses, requests: [], requested_uris: [], addresses: [], **options)
    queue = responses.dup
    BlackCoffeeImageDownloader.new(
      **options,
      address_resolver: ->(_host) { ['93.184.216.34'] },
      http_factory: lambda do |uri, address|
        response = queue.shift
        raise "unexpected HTTP request for #{uri}" unless response

        requested_uris << uri.to_s
        addresses << address
        FakeHttp.new(response, requests)
      end
    )
  end

  def jpeg_bytes(width:, height:)
    body = "\xFF\xD8\xFF\xC0".b
    body << [17].pack('n')
    body << [8].pack('C')
    body << [height, width].pack('n2')
    body << [3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0].pack('C*')
    body << "\xFF\xD9".b
    body
  end

  def split_chunks(body)
    midpoint = body.bytesize / 2
    [body.byteslice(0, midpoint), body.byteslice(midpoint, body.bytesize - midpoint)]
  end
end
