require 'test_helper'
require 'ostruct'

class GooglePlacesBlackCoffeeClientTest < ActiveSupport::TestCase
  def valencian_region
    OpenStruct.new(slug: 'comunidad_valenciana', name: 'Comunidad Valenciana')
  end

  def google_place(id: 'place-1', state: 'Comunitat Valenciana', province: 'València', photos: [photo('photos/one'), photo('photos/two')])
    {
      'id' => id,
      'name' => "places/#{id}",
      'displayName' => { 'text' => 'Café Test' },
      'formattedAddress' => 'Carrer Major 1, 46001 Valencia, Spain',
      'addressComponents' => [
        { 'types' => ['locality'], 'longText' => 'Valencia' },
        { 'types' => ['administrative_area_level_1'], 'longText' => state },
        { 'types' => ['administrative_area_level_2'], 'longText' => province },
        { 'types' => ['country'], 'longText' => 'Spain', 'shortText' => 'ES' }
      ],
      'location' => { 'latitude' => 39.47, 'longitude' => -0.37 },
      'primaryType' => 'cafe',
      'types' => ['cafe', 'food'],
      'photos' => photos
    }
  end

  def photo(name)
    {
      'name' => name,
      'widthPx' => 1200,
      'heightPx' => 800,
      'authorAttributions' => [{ 'displayName' => 'Google user' }]
    }
  end

  def client_with_places(places)
    GooglePlacesBlackCoffeeClient.new(api_key: 'test-key').tap do |client|
      client.define_singleton_method(:fetch_places) do |**_kwargs|
        [places, 1, places.size, { invalid_category_skipped: 0 }]
      end
    end
  end

  def without_dynamic_import_filters
    BlackCoffeeGoogleImportFilter.stub(:enhance_config, ->(_category, config) { config }) { yield }
  end

  def with_google_photo_url_resolution(enabled)
    previous = ENV['BLACK_COFFEE_ALLOW_GOOGLE_PHOTO_URL_RESOLUTION']
    ENV['BLACK_COFFEE_ALLOW_GOOGLE_PHOTO_URL_RESOLUTION'] = enabled ? 'true' : 'false'
    yield
  ensure
    if previous.nil?
      ENV.delete('BLACK_COFFEE_ALLOW_GOOGLE_PHOTO_URL_RESOLUTION')
    else
      ENV['BLACK_COFFEE_ALLOW_GOOGLE_PHOTO_URL_RESOLUTION'] = previous
    end
  end

  test 'search metadata saves photo references without resolving photo URLs by default' do
    client = client_with_places([google_place])
    client.define_singleton_method(:photo_uri_for) do |_photo_name|
      raise 'photo URL resolution should not run in this import mode'
    end

    result = without_dynamic_import_filters do
      client.search(
        region: valencian_region,
        category: 'cafeteria',
        limit: 10,
        metadata: true,
        max_photos_per_place: 2,
        resolve_photo_urls_during_import: false,
        skip_existing_places: false,
        skip_imported_candidates: false,
        strict_region_filter: true,
        require_photos_during_import: true
      )
    end

    candidate = result[:candidates].first
    assert_equal 1, result[:requests_count]
    assert_equal 1, result.dig(:google_requests, :search)
    assert_equal 0, result.dig(:google_requests, :photos)
    assert_equal 2, result.dig(:photos, :references_saved)
    assert_equal 0, result.dig(:photos, :urls_resolved)
    assert_equal [], candidate[:image_urls]
    assert_equal ['photos/one', 'photos/two'], candidate[:google_photo_references].map { |reference| reference[:name] }
  end

  test 'search skips candidates without photos when photos are required' do
    client = client_with_places([google_place(photos: [])])

    result = without_dynamic_import_filters do
      client.search(
        region: valencian_region,
        category: 'cafeteria',
        limit: 10,
        metadata: true,
        resolve_photo_urls_during_import: false,
        skip_existing_places: false,
        skip_imported_candidates: false,
        strict_region_filter: true,
        require_photos_during_import: true
      )
    end

    assert_empty result[:candidates]
    assert_equal 1, result[:no_photo_skipped]
    assert_equal 0, result.dig(:photos, :references_saved)
  end

  test 'search discards places outside the requested autonomous community before photo handling' do
    client = client_with_places([
      google_place(state: 'Región de Murcia', province: 'Murcia')
    ])
    client.define_singleton_method(:photo_uri_for) do |_photo_name|
      raise 'outside-region candidates must be discarded before photo resolution'
    end

    result = without_dynamic_import_filters do
      client.search(
        region: valencian_region,
        category: 'cafeteria',
        limit: 10,
        metadata: true,
        resolve_photo_urls_during_import: true,
        skip_existing_places: false,
        skip_imported_candidates: false,
        strict_region_filter: true,
        require_photos_during_import: true
      )
    end

    assert_empty result[:candidates]
    assert_equal 1, result[:outside_region_skipped]
    assert_equal 0, result.dig(:google_requests, :photos)
  end

  test 'search resolves photo URLs only when explicitly enabled' do
    client = client_with_places([google_place(photos: [photo('photos/one')])])
    client.define_singleton_method(:photo_uri_for) do |photo_name|
      "https://images.example/#{photo_name}"
    end

    result = with_google_photo_url_resolution(true) do
      without_dynamic_import_filters do
        client.search(
          region: valencian_region,
          category: 'cafeteria',
          limit: 10,
          metadata: true,
          resolve_photo_urls_during_import: true,
          skip_existing_places: false,
          skip_imported_candidates: false,
          strict_region_filter: true,
          require_photos_during_import: true
        )
      end
    end

    candidate = result[:candidates].first
    assert_equal ['https://images.example/photos/one'], candidate[:image_urls]
    assert_equal 1, result.dig(:google_requests, :photos)
    assert_equal 1, result.dig(:photos, :urls_resolved)
  end

  test 'search does not resolve photo URLs unless the safety flag allows it' do
    client = client_with_places([google_place(photos: [photo('photos/one')])])
    client.define_singleton_method(:photo_uri_for) do |_photo_name|
      raise 'photo URL resolution must stay blocked by default'
    end

    result = with_google_photo_url_resolution(false) do
      without_dynamic_import_filters do
        client.search(
          region: valencian_region,
          category: 'cafeteria',
          limit: 10,
          metadata: true,
          resolve_photo_urls_during_import: true,
          skip_existing_places: false,
          skip_imported_candidates: false,
          strict_region_filter: true,
          require_photos_during_import: true
        )
      end
    end

    candidate = result[:candidates].first
    assert_equal [], candidate[:image_urls]
    assert_equal 0, result.dig(:google_requests, :photos)
    assert_equal 0, result.dig(:photos, :urls_resolved)
  end

  test 'search can use a lean field mask for dry run requests' do
    captured_field_masks = []
    place = google_place
    client = GooglePlacesBlackCoffeeClient.new(api_key: 'test-key')
    client.define_singleton_method(:post_json) do |_url, _body, field_mask:|
      captured_field_masks << field_mask
      { 'places' => [place], 'nextPageToken' => nil }
    end

    result = without_dynamic_import_filters do
      client.search(
        region: valencian_region,
        category: 'cafeteria',
        limit: 10,
        metadata: true,
        resolve_photo_urls_during_import: false,
        skip_existing_places: false,
        skip_imported_candidates: false,
        strict_region_filter: true,
        require_photos_during_import: true,
        search_field_mask: GooglePlacesBlackCoffeeClient::DRY_RUN_FIELD_MASK
      )
    end

    assert_equal [GooglePlacesBlackCoffeeClient::DRY_RUN_FIELD_MASK], captured_field_masks
    assert_equal 1, result[:raw_candidates_count]
  end

  test 'search skips candidates that already exist in import history before photo handling' do
    client = client_with_places([google_place])
    client.define_singleton_method(:existing_import_candidate_place_ids) do |_places|
      Set.new(['place-1'])
    end
    client.define_singleton_method(:photo_uri_for) do |_photo_name|
      raise 'already imported candidates must be skipped before photo resolution'
    end

    result = without_dynamic_import_filters do
      client.search(
        region: valencian_region,
        category: 'cafeteria',
        limit: 10,
        metadata: true,
        resolve_photo_urls_during_import: true,
        skip_existing_places: false,
        skip_imported_candidates: true,
        strict_region_filter: true,
        require_photos_during_import: true
      )
    end

    assert_empty result[:candidates]
    assert_equal 1, result[:already_imported_skipped]
    assert_equal 0, result.dig(:google_requests, :photos)
  end

  test 'photo URL refresh deduplicates repeated photo references and reuses cache' do
    client = GooglePlacesBlackCoffeeClient.new(api_key: 'test-key')
    requested_uris = []
    client.define_singleton_method(:get_json) do |uri, field_mask: nil|
      requested_uris << uri.to_s
      { 'photoUri' => "https://images.example/#{requested_uris.size}" }
    end

    first_result = with_google_photo_url_resolution(true) do
      client.photo_urls_from_references(
        [photo('photos/one'), photo('photos/one'), photo('photos/two')],
        max_photos: 3
      )
    end
    second_result = with_google_photo_url_resolution(true) do
      client.photo_urls_from_references(
        [photo('photos/one'), photo('photos/two')],
        max_photos: 2
      )
    end

    assert_equal 2, first_result[:requests_count]
    assert_equal 0, second_result[:requests_count]
    assert_equal 2, requested_uris.size
    assert_equal ['https://images.example/1', 'https://images.example/2'], first_result[:image_urls]
    assert_equal first_result[:image_urls], second_result[:image_urls]
  end

  test 'photo URL refresh is blocked by default to avoid recurring Google photo costs' do
    client = GooglePlacesBlackCoffeeClient.new(api_key: 'test-key')
    client.define_singleton_method(:get_json) do |_uri, field_mask: nil|
      raise 'Google photo media endpoint should not be called without safety flag'
    end

    result = with_google_photo_url_resolution(false) do
      client.photo_urls_from_references([photo('photos/one')], max_photos: 1)
    end

    assert_equal [], result[:image_urls]
    assert_equal 0, result[:requests_count]
  end
end
