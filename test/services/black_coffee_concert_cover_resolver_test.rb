require 'test_helper'

class BlackCoffeeConcertCoverResolverTest < ActiveSupport::TestCase
  ExternalSearchResult = Struct.new(
    :status,
    :candidate,
    :candidates,
    :confidence,
    :identifiers,
    :provider_attempts,
    :evidence,
    :error_type,
    :error_message,
    keyword_init: true
  )

  class FakeExternalSearch
    attr_reader :requests_count

    def initialize(result = nil)
      @result = result || ExternalSearchResult.new(
        status: 'not_found',
        identifiers: {},
        provider_attempts: [],
        evidence: {},
        error_type: 'no_external_candidate',
        error_message: 'No external candidate.'
      )
      @requests_count = 0
    end

    def search(_event)
      @requests_count += 1
      @result
    end
  end

  class FakeSourceClient
    attr_reader :robots_requests_count, :detail_requests_count

    def initialize(html: nil, error: nil)
      @html = html
      @error = error
      @robots_requests_count = 0
      @detail_requests_count = 0
    end

    def fetch_event_page(_url)
      @detail_requests_count += 1
      raise error if error

      html
    end

    private

    attr_reader :html, :error
  end

  class FakeDownloader
    def initialize(results = {})
      @results = results
    end

    def download(url)
      results.fetch(url) do
        BlackCoffeeImageDownloader::DownloadResult.new(
          ok?: false,
          error_type: 'http_error',
          error_message: 'HTTP 404',
          http_status: 404
        )
      end
    end

    private

    attr_reader :results
  end

  test 'uses a working image from stored source metadata without opening the source page' do
    image_url = 'https://images.example.test/source.jpg'
    source = FakeSourceClient.new(error: 'source page must not be requested')
    resolver = resolver_with(
      source_client: source,
      downloader: FakeDownloader.new(image_url => successful_download(image_url))
    )

    result = resolver.resolve_for_import(event(image_url: image_url))

    assert result.recovered?
    assert_equal 'source_metadata', result.resolution_source
    assert_equal 0, source.detail_requests_count
    assert_equal 1, resolver.image_download_requests_count
  end

  test 'recovers the Open Graph image from the exact Songkick event page' do
    image_url = 'https://images.example.test/source-page.jpg'
    source = FakeSourceClient.new(html: source_page_html(image_url: image_url))
    resolver = resolver_with(
      source_client: source,
      downloader: FakeDownloader.new(image_url => successful_download(image_url))
    )

    result = resolver.resolve_for_import(event)

    assert result.recovered?
    assert_equal 'source_page', result.resolution_source
    assert_equal 1, source.detail_requests_count
    assert_equal image_url, result.image_url
  end

  test 'uses images from an exact detail page even when JSON-LD is absent' do
    image_url = 'https://images.example.test/detail-only.jpg'
    html = <<~HTML
      <html><head>
        <link rel="canonical" href="https://www.songkick.com/concerts/123-josue-rarujo">
        <meta property="og:image" content="#{image_url}">
      </head><body><h1>Josue Rarujo</h1></body></html>
    HTML
    resolver = resolver_with(
      source_client: FakeSourceClient.new(html: html),
      downloader: FakeDownloader.new(image_url => successful_download(image_url))
    )

    result = resolver.resolve_for_import(event)

    assert result.recovered?
    assert_equal 'source_page', result.resolution_source
    assert_equal 'exact_source_url_without_event_json_ld', result.evidence[:match]
  end

  test 'keeps a transient Songkick outage retryable' do
    source = FakeSourceClient.new(
      error: SongkickConcerts::Client::RequestError.new('temporary Songkick outage')
    )
    resolver = resolver_with(source_client: source)

    resolved = resolver.resolve_for_import(event)

    assert resolved.retryable?
    assert_equal 'source_request_error', resolved.error_type
  end

  test 'treats an HTTP 404 from the exact source event as conclusive' do
    source = FakeSourceClient.new(
      error: SongkickConcerts::Client::RequestError.new('HTTP 404', http_status: 404)
    )
    resolver = resolver_with(source_client: source)

    resolved = resolver.resolve_for_import(event)

    assert resolved.missing?
    assert_equal 'source_event_not_found', resolved.error_type
  end

  test 'does not claim absence when Songkick denies access to the source event' do
    source = FakeSourceClient.new(
      error: SongkickConcerts::Client::RequestError.new('HTTP 403', http_status: 403)
    )
    resolver = resolver_with(source_client: source)

    resolved = resolver.resolve_for_import(event)

    assert resolved.unavailable?
    assert_equal 'source_request_blocked', resolved.error_type
  end

  test 'reports a conclusive absence when no source URL or stored image exists' do
    resolver = resolver_with

    resolved = resolver.resolve_for_import(event(source_url: nil))

    assert resolved.missing?
    assert_equal 'missing_source_url', resolved.error_type
    assert_equal 0, resolver.image_download_requests_count
  end

  test 'caches a conclusive external miss and does not search providers again' do
    external_search = FakeExternalSearch.new
    resolver = resolver_with(external_search: external_search)
    payload = event(
      name: 'Negative Cache Fixture Artist',
      artist_name: 'Negative Cache Fixture Artist',
      source_artist_id: '99001234',
      source_url: nil
    )

    first = resolver.resolve_for_import(payload)
    second = resolver.resolve_for_import(payload)

    assert first.missing?
    assert second.missing?
    assert_equal 1, external_search.requests_count
    cache = BlackCoffeeConcertArtistImageCache.find_by!(identity_key: 'songkick:99001234')
    assert_equal 'not_found', cache.status
    assert second.cache?
  end

  private

  def resolver_with(source_client: FakeSourceClient.new, downloader: FakeDownloader.new, external_search: FakeExternalSearch.new)
    BlackCoffeeConcertCoverResolver.new(
      source_client: source_client,
      downloader: downloader,
      external_search: external_search
    )
  end

  def event(overrides = {})
    {
      name: 'Josue Rarujo',
      start_at: Time.zone.parse('2026-07-24 21:00:00'),
      start_date: Date.new(2026, 7, 24),
      city: 'Alicante',
      venue_name: 'VB Spaces',
      source_url: 'https://www.songkick.com/concerts/123-josue-rarujo',
      source_event_id: '123',
      image_url: nil
    }.merge(overrides)
  end

  def source_page_html(image_url:)
    <<~HTML
      <html>
        <head><meta property="og:image" content="#{image_url}"></head>
        <body>
          <script type="application/ld+json">
            {
              "@type": "MusicEvent",
              "@id": "https://www.songkick.com/concerts/123-josue-rarujo#event",
              "url": "https://www.songkick.com/concerts/123-josue-rarujo",
              "name": "Josue Rarujo at VB Spaces",
              "startDate": "2026-07-24T21:00:00+02:00",
              "performer": [{"name": "Josue Rarujo"}],
              "location": {
                "name": "VB Spaces",
                "address": {"addressLocality": "Alicante", "addressCountry": "Spain"}
              }
            }
          </script>
        </body>
      </html>
    HTML
  end

  def successful_download(url)
    BlackCoffeeImageDownloader::DownloadResult.new(
      ok?: true,
      body: 'image-bytes',
      content_type: 'image/jpeg',
      extension: 'jpg',
      http_status: 200,
      final_url: url
    )
  end
end
