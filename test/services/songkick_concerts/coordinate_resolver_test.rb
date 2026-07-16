require 'test_helper'

class SongkickConcertsCoordinateResolverTest < ActiveSupport::TestCase
  class FakeSourceClient
    attr_reader :calls

    def initialize(html)
      @html = html
      @calls = 0
    end

    def fetch_event_page(_url)
      @calls += 1
      @html
    end
  end

  class FakeGeocoder
    attr_reader :calls

    def initialize(results)
      @results = results
      @calls = []
    end

    def geocode_address(**attributes)
      @calls << attributes
      @results
    end
  end

  class MissingKeyGeocoder
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def geocode_address(**)
      @calls += 1
      raise GooglePlacesBlackCoffeeClient::MissingApiKeyError, 'Falta la clave configurada.'
    end
  end

  setup do
    @created_venue_ids = []
  end

  teardown do
    Venue.where(id: @created_venue_ids).destroy_all if @created_venue_ids.any?
  end

  test 'extracts the exact Songkick venue address and validates a Google Places coordinate match' do
    source = FakeSourceClient.new(detail_html)
    geocoder = FakeGeocoder.new([google_place])
    resolver = resolver_for(source: source, geocoder: geocoder)

    result = resolver.resolve(normalized_event)

    assert result.resolved?
    assert_equal BigDecimal('37.992148'), result.latitude
    assert_equal BigDecimal('-1.116420'), result.longitude
    assert_equal 'google_places_address', result.source
    assert_equal 'high', result.confidence
    assert_equal '4456061', result.source_venue_id
    assert_equal '30007', result.postal_code
    assert_includes result.address, 'Carril molino de Nelva 10'
    assert_equal 1, geocoder.calls.size
    assert_includes geocoder.calls.first[:query], 'Sala Mamba'
    assert_includes geocoder.calls.first[:query], '30007'
  end

  test 'recovers the city as well as the street when the listing location is incomplete' do
    source = FakeSourceClient.new(detail_html)
    geocoder = FakeGeocoder.new([google_place])
    event = normalized_event.merge(city: nil, address: 'Sala Mamba, Spain')

    result = resolver_for(source: source, geocoder: geocoder).resolve(event)

    assert result.resolved?
    assert_equal 1, source.calls
    assert_equal 'Murcia', result.city
    assert_equal 'Carril molino de Nelva 10', result.street_address
    assert_equal '30007', result.postal_code
  end

  test 'uses coordinates published by the exact source detail without external geocoding' do
    html = detail_html(geo: { 'latitude' => '37.992148', 'longitude' => '-1.116420' })
    geocoder = FakeGeocoder.new([google_place])

    result = resolver_for(source: FakeSourceClient.new(html), geocoder: geocoder).resolve(normalized_event)

    assert result.resolved?
    assert_equal 'songkick_detail_schema_org', result.source
    assert_equal 0, geocoder.calls.size
  end

  test 'geocodes a complete listing address without requesting the detail again' do
    source = FakeSourceClient.new('<html></html>')
    geocoder = FakeGeocoder.new([google_place])
    listing_event = normalized_event.merge(
      street_address: 'Carril molino de Nelva 10',
      postal_code: '30007',
      address: 'Carril molino de Nelva 10, Sala Mamba, 30007, Murcia, Spain'
    )

    result = resolver_for(source: source, geocoder: geocoder).resolve(listing_event)

    assert result.resolved?
    assert_equal 'google_places_address', result.source
    assert_equal 0, source.calls
    assert_equal 1, geocoder.calls.size
    assert_includes result.evidence[:signals], 'postal_code'
  end

  test 'reuses a strongly matched non-festival local venue before calling Google' do
    venue = Venue.create!(
      name: 'Sala Mamba referencia local',
      category: 'nightlife',
      description: 'Referencia de prueba',
      address: 'Carril molino de Nelva 10, 30007, Murcia, Spain',
      city: 'Murcia',
      latitude: 37.992148,
      longitude: -1.116420,
      featured: false,
      tags: ['night_club'],
      festival_venue_name: 'Sala Mamba'
    )
    @created_venue_ids << venue.id
    geocoder = FakeGeocoder.new([google_place])

    result = resolver_for(source: FakeSourceClient.new(detail_html), geocoder: geocoder).resolve(normalized_event)

    assert result.resolved?
    assert_equal 'local_venue_exact_match', result.source
    assert_equal venue.id, result.evidence[:matched_venue_id]
    assert_equal 0, geocoder.calls.size
  end

  test 'never reuses a festival as a coordinate identity for a concert' do
    venue = Venue.create!(
      name: 'Sala Mamba festival',
      category: 'festival',
      description: 'Referencia de prueba',
      address: 'Carril molino de Nelva 10, 30007, Murcia, Spain',
      city: 'Murcia',
      latitude: 40.416775,
      longitude: -3.703790,
      featured: false,
      tags: ['festival'],
      festival_venue_name: 'Sala Mamba'
    )
    @created_venue_ids << venue.id
    geocoder = FakeGeocoder.new([google_place])

    result = resolver_for(source: FakeSourceClient.new(detail_html), geocoder: geocoder).resolve(normalized_event)

    assert result.resolved?
    assert_equal 'google_places_address', result.source
    assert_equal 1, geocoder.calls.size
  end

  test 'rejects similarly scored distant Google results as ambiguous' do
    second = google_place(
      id: 'far-away',
      latitude: 40.416775,
      longitude: -3.703790,
      formatted_address: 'Carril molino de Nelva 10, 30007 Murcia, Spain'
    )
    geocoder = FakeGeocoder.new([google_place, second])

    result = resolver_for(source: FakeSourceClient.new(detail_html), geocoder: geocoder).resolve(normalized_event)

    assert result.ambiguous?
    assert_equal 'ambiguous_geocoding', result.error_type
    assert_nil result.latitude
    assert_nil result.longitude
  end

  test 'rejects the same venue name and city when Google returns another street and postal code' do
    wrong_address = google_place(
      id: 'same-name-wrong-address',
      formatted_address: 'Avenida Juan Carlos I 99, 30008 Murcia, Spain',
      postal_code: '30008'
    )

    result = resolver_for(
      source: FakeSourceClient.new(detail_html),
      geocoder: FakeGeocoder.new([wrong_address])
    ).resolve(normalized_event)

    refute result.resolved?
    assert_equal 'not_found', result.status
    assert_equal 'geocoding_not_found', result.error_type
  end

  test 'caches a verified address result and does not repeat the Google request' do
    cache = ActiveSupport::Cache::MemoryStore.new
    geocoder = FakeGeocoder.new([google_place])
    resolver = resolver_for(source: FakeSourceClient.new(detail_html), geocoder: geocoder, cache: cache)

    first = resolver.resolve(normalized_event)
    second = resolver.resolve(normalized_event)

    assert first.resolved?
    assert second.resolved?
    assert_equal 1, geocoder.calls.size
    assert_equal true, second.evidence[:cache_hit]
  end

  test 'does not cache provider unavailability after the Places key is configured' do
    cache = ActiveSupport::Cache::MemoryStore.new
    listing_event = normalized_event.merge(
      street_address: 'Carril molino de Nelva 10',
      postal_code: '30007',
      address: 'Carril molino de Nelva 10, Sala Mamba, 30007, Murcia, Spain'
    )
    unavailable = resolver_for(
      source: FakeSourceClient.new('<html></html>'),
      geocoder: MissingKeyGeocoder.new,
      cache: cache
    ).resolve(listing_event)
    configured_geocoder = FakeGeocoder.new([google_place])

    recovered = resolver_for(
      source: FakeSourceClient.new('<html></html>'),
      geocoder: configured_geocoder,
      cache: cache
    ).resolve(listing_event)

    assert_equal 'unavailable', unavailable.status
    assert recovered.resolved?
    assert_equal 1, configured_geocoder.calls.size
    refute recovered.evidence[:cache_hit]
  end

  test 'does not process festival source URLs through the concert geocoder' do
    source = FakeSourceClient.new(detail_html)
    geocoder = FakeGeocoder.new([google_place])

    result = resolver_for(source: source, geocoder: geocoder).resolve(
      normalized_event.merge(source_url: 'https://www.songkick.com/festivals/123-test', non_concert_like: true)
    )

    refute result.resolved?
    assert_equal 'non_concert_source', result.error_type
    assert_equal 0, source.calls
    assert_equal 0, geocoder.calls.size
  end

  private

  def resolver_for(source:, geocoder:, cache: ActiveSupport::Cache::MemoryStore.new)
    SongkickConcerts::CoordinateResolver.new(
      source_client: source,
      geocoder: geocoder,
      cache: cache,
      logger: Logger.new(nil)
    )
  end

  def normalized_event
    {
      source_url: 'https://www.songkick.com/concerts/43236393-abhir-at-sala-mamba',
      source_event_id: '43236393',
      name: 'Abhir',
      venue_name: 'Sala Mamba',
      address: 'Sala Mamba, Murcia, Spain',
      city: 'Murcia',
      country: 'Spain',
      country_code: 'ES',
      latitude: nil,
      longitude: nil,
      non_concert_like: false
    }
  end

  def detail_html(geo: nil)
    location = {
      '@type' => 'Place',
      'name' => 'Sala Mamba',
      'address' => {
        '@type' => 'PostalAddress',
        'streetAddress' => 'Carril molino de Nelva 10',
        'postalCode' => '30007',
        'addressLocality' => 'Murcia',
        'addressCountry' => 'Spain'
      }
    }
    location['geo'] = geo if geo
    event = {
      '@context' => 'https://schema.org',
      '@type' => 'MusicEvent',
      'name' => 'Abhir @ Sala Mamba',
      'url' => 'https://www.songkick.com/concerts/43236393-abhir-at-sala-mamba',
      'location' => location
    }

    <<~HTML
      <html>
        <head>
          <link rel="canonical" href="https://www.songkick.com/concerts/43236393-abhir-at-sala-mamba">
        </head>
        <body>
          <div class="venue-container">
            <a href="/venues/4456061-sala-mamba">Sala Mamba</a>
          </div>
          <script type="application/ld+json">#{event.to_json}</script>
        </body>
      </html>
    HTML
  end

  def google_place(
    id: 'google-sala-mamba',
    latitude: 37.992148,
    longitude: -1.116420,
    formatted_address: 'Carril Molino de Nelva, 10, 30007 Murcia, Spain',
    postal_code: '30007'
  )
    {
      'id' => id,
      'displayName' => { 'text' => 'Sala Mamba' },
      'formattedAddress' => formatted_address,
      'location' => { 'latitude' => latitude, 'longitude' => longitude },
      'addressComponents' => [
        { 'longText' => postal_code, 'shortText' => postal_code, 'types' => ['postal_code'] },
        { 'longText' => 'Murcia', 'shortText' => 'Murcia', 'types' => ['locality'] },
        { 'longText' => 'España', 'shortText' => 'ES', 'types' => ['country'] }
      ]
    }
  end
end
