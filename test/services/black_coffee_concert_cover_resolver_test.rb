require 'test_helper'

class BlackCoffeeConcertCoverResolverTest < ActiveSupport::TestCase
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

  class FakeSearchClient
    attr_reader :requests_count

    def initialize(results: [], configured: true, error: nil)
      @results = results
      @configured = configured
      @error = error
      @requests_count = 0
    end

    def configured?
      @configured
    end

    def search(_query)
      @requests_count += 1
      raise error if error

      results
    end

    private

    attr_reader :results, :error
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

  test 'uses a working image from source metadata without searching the web' do
    image_url = 'https://images.example.test/source.jpg'
    search = FakeSearchClient.new
    resolver = resolver_with(
      source_client: FakeSourceClient.new(error: 'source page must not be requested'),
      search_client: search,
      downloader: FakeDownloader.new(image_url => successful_download(image_url))
    )

    result = resolver.resolve_for_import(event(image_url: image_url))

    assert result.recovered?
    assert_equal 'source_metadata', result.resolution_source
    assert_equal 0, search.requests_count
    assert_equal 1, resolver.image_download_requests_count
  end

  test 'accepts web search only when name date and location match' do
    image_url = 'https://images.example.test/exact-event.jpg'
    result = search_result(
      title: 'Josue Rarujo en Alicante - 24/07/2026',
      description: 'Concierto de Josue Rarujo en VB Spaces, Alicante, el 24 de julio de 2026.',
      image_url: image_url
    )
    resolver = resolver_with(
      search_client: FakeSearchClient.new(results: [result]),
      downloader: FakeDownloader.new(image_url => successful_download(image_url))
    )

    resolved = resolver.resolve_for_import(event)

    assert resolved.recovered?
    assert_equal 'brave_search', resolved.resolution_source
    assert_operator resolved.confidence, :>=, 90
    assert_equal 1, resolver.search_requests_count
  end

  test 'tries the next strict search match when the first image cannot be downloaded' do
    broken_url = 'https://images.example.test/broken-event.jpg'
    working_url = 'https://images.example.test/working-event.jpg'
    results = [broken_url, working_url].map do |image_url|
      search_result(
        title: 'Josue Rarujo en Alicante - 24/07/2026',
        description: 'Concierto de Josue Rarujo en VB Spaces, Alicante, el 24 de julio de 2026.',
        image_url: image_url
      )
    end
    resolver = resolver_with(
      search_client: FakeSearchClient.new(results: results),
      downloader: FakeDownloader.new(working_url => successful_download(working_url))
    )

    resolved = resolver.resolve_for_import(event)

    assert resolved.recovered?
    assert_equal working_url, resolved.image_url
    assert_equal 2, resolver.image_download_requests_count
  end

  test 'rejects a visually plausible search result for the wrong date' do
    image_url = 'https://images.example.test/wrong-date.jpg'
    result = search_result(
      title: 'Josue Rarujo en Alicante - 25/07/2026',
      description: 'Concierto de Josue Rarujo en VB Spaces, Alicante, el 25 de julio de 2026.',
      image_url: image_url
    )
    resolver = resolver_with(search_client: FakeSearchClient.new(results: [result]))

    resolved = resolver.resolve_for_import(event)

    assert resolved.missing?
    assert_equal 'no_confident_search_match', resolved.error_type
    assert_equal 0, resolver.image_download_requests_count
  end

  test 'keeps a transient source outage retryable even when search has no match' do
    source = FakeSourceClient.new(
      error: SongkickConcerts::Client::RequestError.new('temporary Songkick outage')
    )
    resolver = resolver_with(source_client: source, search_client: FakeSearchClient.new(results: []))

    resolved = resolver.resolve_for_import(event)

    assert resolved.retryable?
    assert_equal 'source_request_error', resolved.error_type
  end

  test 'treats a missing source event as conclusive when strict web search also has no match' do
    source = FakeSourceClient.new(
      error: SongkickConcerts::Client::RequestError.new('HTTP 404', http_status: 404)
    )
    resolver = resolver_with(source_client: source, search_client: FakeSearchClient.new(results: []))

    resolved = resolver.resolve_for_import(event)

    assert resolved.missing?
    assert_equal 'no_confident_search_match', resolved.error_type
  end

  test 'does not claim absence when Songkick denies access to the source event' do
    source = FakeSourceClient.new(
      error: SongkickConcerts::Client::RequestError.new('HTTP 403', http_status: 403)
    )
    resolver = resolver_with(source_client: source, search_client: FakeSearchClient.new(results: []))

    resolved = resolver.resolve_for_import(event)

    assert resolved.unavailable?
    assert_equal 'source_request_blocked', resolved.error_type
  end

  test 'does not claim absence when external search is not configured' do
    resolver = resolver_with(search_client: FakeSearchClient.new(configured: false))

    resolved = resolver.resolve_for_import(event(source_url: nil))

    assert resolved.unavailable?
    assert_equal 'search_not_configured', resolved.error_type
  end

  private

  def resolver_with(source_client: FakeSourceClient.new, search_client: FakeSearchClient.new, downloader: FakeDownloader.new)
    BlackCoffeeConcertCoverResolver.new(
      source_client: source_client,
      search_client: search_client,
      downloader: downloader,
      external_search_enabled: true
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

  def search_result(title:, description:, image_url:)
    BlackCoffeeConcertCoverSearch::BraveClient::SearchResult.new(
      title: title,
      description: description,
      image_url: image_url,
      page_url: 'https://tickets.example.test/josue-rarujo-alicante-2026',
      width: 1200,
      height: 1600,
      publisher: 'Tickets Example'
    )
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
