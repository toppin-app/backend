require 'test_helper'

class BlackCoffeeConcertCoverSearchHttpClientTest < ActiveSupport::TestCase
  class FakeResponse
    attr_reader :code

    def initialize(code:, body: '', headers: {})
      @code = code.to_s
      @body = body
      @headers = headers.transform_keys { |key| key.to_s.downcase }
    end

    def [](key)
      headers[key.to_s.downcase]
    end

    def read_body
      yield body
    end

    private

    attr_reader :body, :headers
  end

  class FakeHttp
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def start
      yield self
    end

    def request(request)
      @last_request = request
      yield response
    end

    private

    attr_reader :response
  end

  test 'parses JSON with a meaningful user agent and an allowlisted public destination' do
    http = FakeHttp.new(FakeResponse.new(code: 200, body: '{"artists":[]}'))
    client = client_for(http)

    result = client.get('https://musicbrainz.org/ws/2/artist', params: { fmt: 'json', limit: 5 })

    assert result.ok?
    assert_equal({ 'artists' => [] }, result.json)
    assert_equal 1, client.requests_count
    assert_equal 'FixtureConcertCoverSearch/1.0 (tests@example.test)', http.last_request['User-Agent']
    assert_includes http.last_request.path, 'fmt=json'
    assert_includes http.last_request.path, 'limit=5'
  end

  test 'classifies 429 and preserves Retry-After' do
    http = FakeHttp.new(FakeResponse.new(code: 429, headers: { 'Retry-After' => '17' }))

    result = client_for(http).get('https://musicbrainz.org/ws/2/artist')

    assert result.retryable?
    assert_equal 'rate_limited', result.error_type
    assert_equal 429, result.http_status
    assert_equal 17, result.retry_after
  end

  test 'classifies upstream 5xx as retryable' do
    http = FakeHttp.new(FakeResponse.new(code: 503))

    result = client_for(http).get('https://musicbrainz.org/ws/2/artist')

    assert result.retryable?
    assert_equal 'upstream_server_error', result.error_type
    assert_equal 503, result.http_status
  end

  test 'does not follow a redirect outside the exact host allowlist' do
    http = FakeHttp.new(
      FakeResponse.new(code: 302, headers: { 'Location' => 'https://attacker.example/private.json' })
    )
    client = client_for(http)

    result = client.get('https://musicbrainz.org/ws/2/artist')

    assert_equal 'unavailable', result.status
    assert_equal 'blocked_host', result.error_type
    assert_equal 1, client.requests_count
  end

  test 'blocks an allowlisted host when DNS resolves to a private address' do
    factory_called = false
    client = BlackCoffeeConcertCoverSearch::HttpClient.new(
      allowed_hosts: ['musicbrainz.org'],
      address_resolver: ->(_host) { ['127.0.0.1'] },
      http_factory: ->(_uri, _address) { factory_called = true }
    )

    result = client.get('https://musicbrainz.org/ws/2/artist')

    assert_equal 'unavailable', result.status
    assert_equal 'blocked_destination', result.error_type
    assert_equal false, factory_called
    assert_equal 0, client.requests_count
  end

  test 'normalizes an IPv4-mapped IPv6 address before applying private-network rules' do
    factory_called = false
    client = BlackCoffeeConcertCoverSearch::HttpClient.new(
      allowed_hosts: ['musicbrainz.org'],
      address_resolver: ->(_host) { ['::ffff:127.0.0.1'] },
      http_factory: ->(_uri, _address) { factory_called = true }
    )

    result = client.get('https://musicbrainz.org/ws/2/artist')

    assert_equal 'unavailable', result.status
    assert_equal 'blocked_destination', result.error_type
    assert_equal false, factory_called
    assert_equal 0, client.requests_count
  end

  private

  def client_for(http)
    BlackCoffeeConcertCoverSearch::HttpClient.new(
      allowed_hosts: ['musicbrainz.org'],
      user_agent: 'FixtureConcertCoverSearch/1.0 (tests@example.test)',
      address_resolver: ->(_host) { ['93.184.216.34'] },
      http_factory: ->(_uri, _address) { http }
    )
  end
end
