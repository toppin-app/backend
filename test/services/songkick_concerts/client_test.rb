require 'test_helper'

class SongkickConcertsClientTest < ActiveSupport::TestCase
  class StubClient < SongkickConcerts::Client
    attr_reader :requested_urls

    def initialize(responses)
      super(request_delay_seconds: 0)
      @responses = responses.dup
      @requested_urls = []
    end

    private

    def http_get(uri)
      requested_urls << uri.to_s
      @responses.fetch(uri.to_s)
    end

    def respect_delay!
      nil
    end
  end

  test 'follows relative redirects within Songkick and records the final detail URL' do
    original = 'https://www.songkick.com/concerts/123-old-slug'
    canonical = 'https://www.songkick.com/concerts/123-current-slug'
    responses = {
      'https://www.songkick.com/robots.txt' => http_ok("User-agent: *\nAllow: /\n"),
      original => http_redirect('/concerts/123-current-slug'),
      canonical => http_ok('<html>concert</html>')
    }
    client = StubClient.new(responses)

    body = client.fetch_event_page(original)

    assert_equal '<html>concert</html>', body
    assert_equal canonical, client.last_response_url
    assert_equal [
      'https://www.songkick.com/robots.txt',
      original,
      canonical
    ], client.requested_urls
  end

  test 'rejects redirects that leave the Songkick HTTPS origin' do
    original = 'https://www.songkick.com/concerts/123-old-slug'
    responses = {
      'https://www.songkick.com/robots.txt' => http_ok("User-agent: *\nAllow: /\n"),
      original => http_redirect('https://example.test/stolen')
    }
    client = StubClient.new(responses)

    error = assert_raises(SongkickConcerts::Client::RequestError) do
      client.fetch_event_page(original)
    end

    assert_match(/no pertenece a Songkick/i, error.message)
  end

  private

  def http_ok(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['content-type'] = 'text/html; charset=utf-8'
    response.instance_variable_set(:@read, true)
    response.body = body
    response
  end

  def http_redirect(location)
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['location'] = location
    response.instance_variable_set(:@read, true)
    response.body = ''
    response
  end
end
