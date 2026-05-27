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

  test 'search metadata saves photo references without resolving photo URLs by default' do
    client = client_with_places([google_place])
    client.define_singleton_method(:photo_uri_for) do |_photo_name|
      raise 'photo URL resolution should not run in this import mode'
    end

    result = client.search(
      region: valencian_region,
      category: 'cafeteria',
      limit: 10,
      metadata: true,
      max_photos_per_place: 2,
      resolve_photo_urls_during_import: false,
      skip_existing_places: false,
      strict_region_filter: true,
      require_photos_during_import: true
    )

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

    result = client.search(
      region: valencian_region,
      category: 'cafeteria',
      limit: 10,
      metadata: true,
      resolve_photo_urls_during_import: false,
      skip_existing_places: false,
      strict_region_filter: true,
      require_photos_during_import: true
    )

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

    result = client.search(
      region: valencian_region,
      category: 'cafeteria',
      limit: 10,
      metadata: true,
      resolve_photo_urls_during_import: true,
      skip_existing_places: false,
      strict_region_filter: true,
      require_photos_during_import: true
    )

    assert_empty result[:candidates]
    assert_equal 1, result[:outside_region_skipped]
    assert_equal 0, result.dig(:google_requests, :photos)
  end

  test 'search resolves photo URLs only when explicitly enabled' do
    client = client_with_places([google_place(photos: [photo('photos/one')])])
    client.define_singleton_method(:photo_uri_for) do |photo_name|
      "https://images.example/#{photo_name}"
    end

    result = client.search(
      region: valencian_region,
      category: 'cafeteria',
      limit: 10,
      metadata: true,
      resolve_photo_urls_during_import: true,
      skip_existing_places: false,
      strict_region_filter: true,
      require_photos_during_import: true
    )

    candidate = result[:candidates].first
    assert_equal ['https://images.example/photos/one'], candidate[:image_urls]
    assert_equal 1, result.dig(:google_requests, :photos)
    assert_equal 1, result.dig(:photos, :urls_resolved)
  end
end
