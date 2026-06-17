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
  end

  test 'marks non Spanish festivals as outside country' do
    normalized = FanMusicFest::Normalizer.new.normalize(raw_event(country: 'Portugal'))

    assert_equal 'PT', normalized[:country_code]
    assert normalized[:outside_country]
    refute normalized[:valid]
  end
end
