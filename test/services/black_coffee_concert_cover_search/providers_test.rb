require 'test_helper'

class BlackCoffeeConcertCoverSearchProvidersTest < ActiveSupport::TestCase
  ALOK_MBID = '78f76d66-210a-41ca-b3e3-79a9c5f9eed1'.freeze

  class FakeJsonClient
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def get(url, params:)
      calls << { url: url, params: params }
      responses.shift || raise("Unexpected request to #{url}")
    end

    private

    attr_reader :responses
  end

  test 'MusicBrainz keeps aliases, country, genres, URL relations, and stable crosslinks' do
    client = FakeJsonClient.new(
      ok_response(
        'artists' => [
          { 'id' => ALOK_MBID, 'name' => 'Alok', 'score' => 100 }
        ]
      ),
      ok_response(
        'id' => ALOK_MBID,
        'name' => 'Alok',
        'aliases' => [{ 'name' => 'Alok Achkar' }],
        'country' => 'BR',
        'genres' => [{ 'name' => 'electronic' }],
        'relations' => [
          { 'url' => { 'resource' => 'https://www.songkick.com/artists/4646863-alok' } },
          { 'url' => { 'resource' => 'https://www.wikidata.org/wiki/Q28007321' } },
          { 'url' => { 'resource' => 'https://www.alokmusic.com/' } }
        ]
      )
    )
    sleeps = []
    provider = BlackCoffeeConcertCoverSearch::Providers::MusicBrainz.new(
      client: client,
      minimum_interval: 0,
      lookup_limit: 1,
      sleeper: ->(seconds) { sleeps << seconds },
      clock: -> { 0.0 }
    )

    result = provider.search(search_context(artist_name: 'Alok'))

    assert_equal 'ok', result.status
    assert_equal 2, result.requests_count
    identity = result.identities.first
    assert_equal ['Alok Achkar'], identity[:aliases]
    assert_equal 'BR', identity[:country]
    assert_equal ['electronic'], identity[:genres]
    assert_equal ['https://www.alokmusic.com/'], identity[:official_urls]
    assert_equal ALOK_MBID, identity.dig(:identifiers, :musicbrainz_id)
    assert_equal '4646863', identity.dig(:identifiers, :songkick_id)
    assert_equal 'Q28007321', identity.dig(:identifiers, :wikidata_id)
    assert_includes identity.dig(:evidence, :relation_urls), 'https://www.wikidata.org/wiki/Q28007321'
    assert_equal [1.0], sleeps
  end

  test 'Wikidata resolves a Songkick identifier and validates QID and P434 values' do
    entity = {
      'id' => 'Q28007321',
      'labels' => {
        'en' => { 'language' => 'en', 'value' => 'Alok' }
      },
      'aliases' => {
        'en' => [{ 'language' => 'en', 'value' => 'Alok Achkar' }]
      },
      'descriptions' => {
        'en' => { 'language' => 'en', 'value' => 'Brazilian disc jockey' }
      },
      'claims' => {
        'P434' => string_claims(ALOK_MBID, 'not-a-mbid'),
        'P3478' => string_claims('4646863', 'invalid-songkick-id'),
        'P18' => string_claims('Alok promotional portrait.jpg'),
        'P856' => string_claims('https://www.alokmusic.com/'),
        'P31' => entity_claims('Q5'),
        'P106' => entity_claims('Q130857'),
        'P136' => entity_claims('Q9778'),
        'P27' => entity_claims('Q155')
      },
      'sitelinks' => {
        'enwiki' => { 'site' => 'enwiki', 'title' => 'Alok (DJ)' },
        'eswiki' => { 'site' => 'eswiki', 'title' => 'Alok' }
      }
    }
    client = FakeJsonClient.new(
      ok_response('query' => { 'search' => [{ 'title' => 'Q28007321' }] }),
      ok_response('entities' => { 'Q28007321' => entity }),
      ok_response(
        'entities' => {
          'Q5' => labelled_entity('human'),
          'Q130857' => labelled_entity('disc jockey'),
          'Q9778' => labelled_entity('electronic music'),
          'Q155' => labelled_entity('Brazil')
        }
      )
    )
    provider = BlackCoffeeConcertCoverSearch::Providers::Wikidata.new(client: client)

    result = provider.search(search_context(artist_name: 'Alok', songkick_artist_id: '4646863'))

    assert_equal 'ok', result.status
    assert_equal 3, result.requests_count
    assert_equal 'haswbstatement:P3478=4646863', client.calls.first.dig(:params, :srsearch)
    identity = result.identities.first
    assert_equal 'Q28007321', identity.dig(:identifiers, :wikidata_id)
    assert_equal ALOK_MBID, identity.dig(:identifiers, :musicbrainz_id)
    assert_equal '4646863', identity.dig(:identifiers, :songkick_id)
    assert_equal [ALOK_MBID], identity.dig(:evidence, :musicbrainz_ids)
    assert_equal ['4646863'], identity.dig(:evidence, :songkick_ids)
    assert_equal 'Alok promotional portrait.jpg', identity[:image_file]
    assert_equal 'Brazil', identity[:country]
    assert_includes identity[:genres], 'electronic music'
    assert_equal true, identity.dig(:evidence, :musical_entity)
    assert_equal 'Alok (DJ)', identity.dig(:sitelinks, 'enwiki')
  end

  test 'Commons returns only a technically useful image with reusable license attribution' do
    client = FakeJsonClient.new(
      commons_response(
        license_name: 'CC BY 2.0',
        artist: '<a href="https://photographer.example">Fixture Photographer</a>'
      )
    )
    provider = BlackCoffeeConcertCoverSearch::Providers::WikimediaCommons.new(client: client)
    identity = wikidata_identity

    result = provider.search(search_context(artist_name: 'Alok').merge(identities: [identity]))

    assert_equal 'ok', result.status
    assert_equal 1, result.requests_count
    assert_equal 'File:Alok promotional portrait.jpg', client.calls.first.dig(:params, :titles)
    candidate = result.candidates.first
    assert_instance_of BlackCoffeeConcertCoverSearch::Candidate, candidate
    assert_equal 'https://upload.wikimedia.org/thumb/alok.jpg', candidate.image_url
    assert_equal 918, candidate.width
    assert_equal 1_200, candidate.height
    assert_equal 'CC BY 2.0', candidate.evidence.dig(:license, :name)
    assert_equal 'Fixture Photographer', candidate.evidence.dig(:license, :artist)
    assert_equal 'Fixture Photographer', candidate.evidence.dig(:attribution, :text)
    assert_equal ALOK_MBID, candidate.identifiers[:musicbrainz_id]
  end

  test 'Commons rejects a noncommercial image even when it has attribution' do
    client = FakeJsonClient.new(
      commons_response(
        license_name: 'CC BY-NC 4.0',
        artist: 'Fixture Photographer'
      )
    )
    provider = BlackCoffeeConcertCoverSearch::Providers::WikimediaCommons.new(client: client)

    result = provider.search(search_context(artist_name: 'Alok').merge(identities: [wikidata_identity]))

    assert_equal 'not_found', result.status
    assert_equal 'commons_not_found', result.error_type
    assert_equal 'unsupported_license', result.evidence.dig(:rejected_files, 0, :reason)
  end

  private

  def ok_response(json)
    BlackCoffeeConcertCoverSearch::HttpClient::Response.new(
      status: 'ok',
      json: json,
      http_status: 200
    )
  end

  def search_context(attributes)
    {
      artist: BlackCoffeeConcertCoverSearch::ArtistContext.build(attributes),
      identities: [],
      candidates: []
    }
  end

  def string_claims(*values)
    values.map do |value|
      {
        'rank' => 'normal',
        'mainsnak' => { 'datavalue' => { 'value' => value } }
      }
    end
  end

  def entity_claims(*qids)
    qids.map do |qid|
      {
        'rank' => 'normal',
        'mainsnak' => { 'datavalue' => { 'value' => { 'entity-type' => 'item', 'id' => qid } } }
      }
    end
  end

  def labelled_entity(label)
    { 'labels' => { 'en' => { 'language' => 'en', 'value' => label } } }
  end

  def wikidata_identity
    {
      provider: 'wikidata',
      name: 'Alok',
      aliases: [],
      country: 'Brazil',
      genres: ['electronic music'],
      image_file: 'Alok promotional portrait.jpg',
      identifiers: {
        wikidata_id: 'Q28007321',
        musicbrainz_id: ALOK_MBID,
        songkick_id: '4646863'
      },
      evidence: { musical_entity: true }
    }
  end

  def commons_response(license_name:, artist:)
    ok_response(
      'query' => {
        'pages' => {
          '1' => {
            'title' => 'File:Alok promotional portrait.jpg',
            'imageinfo' => [
              {
                'url' => 'https://upload.wikimedia.org/alok.jpg',
                'thumburl' => 'https://upload.wikimedia.org/thumb/alok.jpg',
                'descriptionurl' => 'https://commons.wikimedia.org/wiki/File:Alok_promotional_portrait.jpg',
                'width' => 1_408,
                'height' => 1_840,
                'thumbwidth' => 918,
                'thumbheight' => 1_200,
                'mime' => 'image/jpeg',
                'sha1' => 'fixture-sha1',
                'extmetadata' => {
                  'LicenseShortName' => { 'value' => license_name },
                  'LicenseUrl' => { 'value' => 'https://creativecommons.org/licenses/by/2.0/' },
                  'Artist' => { 'value' => artist },
                  'AttributionRequired' => { 'value' => 'true' }
                }
              }
            ]
          }
        }
      }
    )
  end
end
