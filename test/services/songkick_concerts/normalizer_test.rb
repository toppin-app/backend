require 'test_helper'

class SongkickConcertsNormalizerTest < ActiveSupport::TestCase
  def raw_event(country: 'Spain', url: 'https://www.songkick.com/concerts/123-test-concert')
    {
      '@id' => "#{url}#event",
      '@type' => 'MusicEvent',
      'name' => 'Artist Uno at Sala Test',
      'url' => url,
      'startDate' => '2026-11-20T21:00:00',
      'endDate' => '2026-11-20T23:30:00',
      'image' => 'https://images.sk-static.com/images/media/profile_images/test.jpg',
      'description' => 'A properly long Songkick concert description that should stay pending editorial review.',
      'performer' => [
        { 'name' => 'Artist Uno', 'genre' => ['indie', 'rock'] },
        { 'name' => 'Artist Dos', 'genre' => 'pop' }
      ],
      'offers' => { 'url' => 'https://tickets.example/songkick-test' },
      'location' => {
        'name' => 'Sala Test',
        'address' => {
          'streetAddress' => 'Calle Test 1',
          'postalCode' => '28001',
          'addressLocality' => 'Madrid',
          'addressRegion' => 'Comunidad de Madrid',
          'addressCountry' => country
        },
        'geo' => {
          'latitude' => '40.416775',
          'longitude' => '-3.703790'
        }
      }
    }
  end

  test 'normalizes Spanish concert data into a valid Black Coffee candidate' do
    normalized = SongkickConcerts::Normalizer.new.normalize(raw_event)

    assert_equal 'songkick', normalized[:source]
    assert_equal 'Artist Uno + Artist Dos', normalized[:name]
    assert_equal 'ES', normalized[:country_code]
    assert_equal Date.new(2026, 11, 20), normalized[:start_date]
    assert_equal Time.zone.parse('2026-11-20T21:00:00'), normalized[:start_at]
    assert_equal Time.zone.parse('2026-11-20T23:30:00'), normalized[:end_at]
    assert normalized[:valid]
    refute normalized[:outside_country]
    refute normalized[:non_concert_like]
    assert_equal 'Sala Test', normalized[:venue_name]
    assert_equal 'Calle Test 1', normalized[:street_address]
    assert_equal '28001', normalized[:postal_code]
    assert_equal 'Calle Test 1, Sala Test, 28001, Madrid, Comunidad de Madrid, Spain', normalized[:address]
    assert_equal '28001', normalized[:locations].first['postalCode']
    assert_equal 'Madrid', normalized[:city]
    assert_equal BigDecimal('40.416775'), normalized[:latitude]
    assert_equal 'schema_org', normalized[:coordinates_source]
    assert_equal 'https://tickets.example/songkick-test', normalized[:ticket_url]
    assert_equal %w[indie rock pop], normalized[:genres]
    assert_equal 'needs_review', normalized[:source_description_status]
    assert normalized[:event_dedupe_key].present?
  end

  test 'supports a single performer hash without treating hash pairs as artists' do
    payload = raw_event
    payload['performer'] = { 'name' => 'Solo Artist', 'genre' => 'jazz' }

    normalized = SongkickConcerts::Normalizer.new.normalize(payload)

    assert_equal ['Solo Artist'], normalized[:performers]
    assert_equal 'Solo Artist', normalized[:name]
    assert_equal ['jazz'], normalized[:genres]
  end

  test 'preserves performer identity details and the stable Songkick artist id' do
    payload = raw_event
    payload['performer'] = {
      '@type' => 'MusicGroup',
      'name' => 'Alok',
      'genre' => %w[electronic pop],
      'sameAs' => [
        '/artists/4646863-alok?utm_source=microformat',
        'https://www.alokmusic.com/'
      ],
      'image' => { 'contentUrl' => '//images.sk-static.com/artists/4646863/large_avatar' }
    }

    normalized = SongkickConcerts::Normalizer.new.normalize(payload)
    performer = normalized[:performer_details].first

    assert_equal ['Alok'], normalized[:performers]
    assert_equal 'Alok', normalized[:artist_name]
    assert_equal '4646863', normalized[:source_artist_id]
    assert_equal ['4646863'], normalized[:source_artist_ids]
    assert_equal 'Alok', performer[:name]
    assert_equal %w[electronic pop], performer[:genres]
    assert_equal '4646863', performer[:source_artist_id]
    assert_equal 'https://www.songkick.com/artists/4646863-alok?utm_source=microformat', performer[:source_url]
    assert_equal 'https://www.alokmusic.com/', performer[:official_url]
    assert_includes performer[:same_as], 'https://www.alokmusic.com/'
    assert_equal ['https://images.sk-static.com/artists/4646863/large_avatar'], performer[:image_urls]
  end

  test 'normalizes image candidates and skips a placeholder before ranking quality' do
    payload = raw_event
    payload['image'] = [
      '//assets.sk-static.com/images/default_images/large_avatar/default-artist.png',
      '/images/artists/123/medium_avatar',
      '//images.sk-static.com/images/media/profile_images/artists/123/huge_avatar'
    ]

    normalized = SongkickConcerts::Normalizer.new.normalize(payload)

    assert_equal 'https://images.sk-static.com/images/media/profile_images/artists/123/huge_avatar', normalized[:image_url]
    assert_equal [
      'https://images.sk-static.com/images/media/profile_images/artists/123/huge_avatar',
      'https://www.songkick.com/images/artists/123/medium_avatar'
    ], normalized[:image_urls]
    assert_equal normalized[:image_urls], normalized[:image_candidates]
  end

  test 'marks non Spanish concerts as outside country' do
    normalized = SongkickConcerts::Normalizer.new.normalize(raw_event(country: 'Portugal'))

    assert_equal 'PT', normalized[:country_code]
    assert normalized[:outside_country]
    refute normalized[:valid]
  end

  test 'detects non-concert Songkick events so the concert importer can skip them' do
    normalized = SongkickConcerts::Normalizer.new.normalize(
      raw_event(url: 'https://www.songkick.com/festivals/999-test-festival')
    )

    assert normalized[:non_concert_like]
  end

  test 'handles incomplete payloads without raising' do
    normalized = SongkickConcerts::Normalizer.new.normalize(nil)

    assert_nil normalized[:name]
    assert_nil normalized[:source_url]
    refute normalized[:valid]
  end
end
