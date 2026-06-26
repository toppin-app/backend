require 'test_helper'

class FanMusicFestNormalizerTest < ActiveSupport::TestCase
  def raw_event(country: 'Espana')
    {
      '@id' => 'https://fanmusicfest.com/content/test-fest-2026#event',
      'name' => 'Test Fest 2026 | Cartel y entradas',
      'url' => 'https://fanmusicfest.com/content/test-fest-2026',
      'startDate' => '2026-07-10',
      'endDate' => '2026-07-12',
      'image' => { 'url' => 'https://fanmusicfest.com/sites/default/files/test.png' },
      'organizer' => { 'name' => 'Test Fest' },
      'description' => 'Una descripcion extensa del festival preparada para revision editorial antes de publicarse.',
      'performer' => [{ 'name' => 'Artista Uno' }, { 'name' => 'Artista Dos' }],
      'location' => {
        'name' => 'Recinto Test',
        'address' => {
          'addressLocality' => 'Valencia',
          'addressRegion' => 'Valencia',
          'addressCountry' => country
        },
        'geo' => {
          'latitude' => '39.4699',
          'longitude' => '-0.3763'
        }
      }
    }
  end

  test 'normalizes Spanish festival data into a valid Black Coffee candidate' do
    normalized = FanMusicFest::Normalizer.new.normalize(raw_event)

    assert_equal 'Test Fest', normalized[:name]
    assert_equal 'ES', normalized[:country_code]
    assert_equal Date.new(2026, 7, 10), normalized[:start_date]
    assert normalized[:valid]
    refute normalized[:outside_country]
    assert_equal 'https://fanmusicfest.com/sites/default/files/test.png', normalized[:image_url]
    assert_equal 'needs_review', normalized[:source_description_status]
    assert_equal 'es', normalized[:source_description_language]
    assert_equal %w[Artista\ Uno Artista\ Dos], normalized[:performers]
    assert_equal 'schema_org', normalized[:coordinates_source]
    assert_equal 'high', normalized[:coordinates_confidence]
  end

  test 'marks non Spanish festivals as outside country' do
    normalized = FanMusicFest::Normalizer.new.normalize(raw_event(country: 'Portugal'))

    assert_equal 'PT', normalized[:country_code]
    assert normalized[:outside_country]
    refute normalized[:valid]
  end

  test 'keeps Spanish festivals valid when coordinates are unavailable' do
    payload = raw_event
    payload['location'].delete('geo')

    normalized = FanMusicFest::Normalizer.new.normalize(payload)

    assert normalized[:valid]
    assert_nil normalized[:latitude]
    assert_nil normalized[:longitude]
  end

  test 'preserves multiple festival locations when schema org provides an array' do
    payload = raw_event
    payload['location'] = [
      {
        'name' => 'Puerto de Vega',
        'address' => {
          'addressLocality' => 'Navia',
          'addressRegion' => 'Asturias',
          'addressCountry' => 'Espana'
        },
        'geo' => {
          'latitude' => '43.56',
          'longitude' => '-6.64'
        }
      },
      {
        'name' => 'Navia',
        'address' => {
          'addressLocality' => 'Navia',
          'addressRegion' => 'Asturias',
          'addressCountry' => 'Espana'
        },
        'geo' => {
          'latitude' => '43.54',
          'longitude' => '-6.72'
        }
      }
    ]

    normalized = FanMusicFest::Normalizer.new.normalize(payload)

    assert normalized[:valid]
    assert_equal 2, normalized[:locations].size
    assert_equal 'Puerto de Vega', normalized[:locations].first['name']
    assert_equal BigDecimal('43.56'), normalized[:locations].first.dig('coordinates', 'latitude')
    assert_equal 'schema_org', normalized[:locations].first['coordinatesSource']
  end

  test 'marks incomplete festivals invalid instead of raising when location is missing' do
    normalized = FanMusicFest::Normalizer.new.normalize(
      '@id' => 'https://fanmusicfest.com/content/incomplete-fest-2026#event',
      'name' => 'Incomplete Fest 2026',
      'url' => 'https://fanmusicfest.com/content/incomplete-fest-2026'
    )

    assert_equal 'Incomplete Fest', normalized[:name]
    assert_equal 'https://fanmusicfest.com/content/incomplete-fest-2026', normalized[:source_url]
    assert_equal 'Direccion pendiente de revisar', normalized[:address]
    refute normalized[:valid]
    refute normalized[:outside_country]
  end

  test 'handles an empty payload without raising' do
    normalized = FanMusicFest::Normalizer.new.normalize(nil)

    assert_nil normalized[:name]
    assert_nil normalized[:source_url]
    refute normalized[:valid]
  end
end
