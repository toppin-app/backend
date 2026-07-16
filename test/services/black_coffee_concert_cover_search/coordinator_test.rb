require 'test_helper'

class BlackCoffeeConcertCoverSearchCoordinatorTest < ActiveSupport::TestCase
  ALOK_MBID = '78f76d66-210a-41ca-b3e3-79a9c5f9eed1'.freeze
  SECOND_MBID = '6f37f5d6-25c5-4d9d-8f3f-c56d62744688'.freeze

  class FakeProvider
    attr_reader :key, :calls

    def initialize(key, result = nil, &implementation)
      @key = key
      @result = result
      @implementation = implementation
      @calls = []
    end

    def search(context)
      calls << context
      implementation ? implementation.call(context) : result
    end

    private

    attr_reader :result, :implementation
  end

  test 'finds the reliable Alok identity through MusicBrainz, Wikidata, and Commons' do
    musicbrainz = musicbrainz_identity(
      name: 'Alok',
      mbid: ALOK_MBID,
      qid: 'Q28007321',
      songkick_id: '4646863'
    )
    wikidata = wikidata_identity(
      name: 'Alok',
      mbid: ALOK_MBID,
      qid: 'Q28007321',
      songkick_id: '4646863',
      genres: %w[electronic pop]
    )
    candidate = commons_candidate(identity: wikidata)

    providers = [
      FakeProvider.new(
        'musicbrainz',
        provider_ok(identities: [musicbrainz], requests_count: 2)
      ),
      FakeProvider.new('wikidata') do |context|
        assert_includes context[:identities], musicbrainz
        provider_ok(identities: [wikidata], requests_count: 2)
      end,
      FakeProvider.new('wikimedia_commons') do |context|
        assert_includes context[:identities], wikidata
        provider_ok(candidates: [candidate], requests_count: 1)
      end
    ]
    coordinator = BlackCoffeeConcertCoverSearch::Coordinator.new(providers: providers)

    result = coordinator.search(
      artist_name: 'Alok',
      songkick_artist_id: '4646863',
      genres: %w[electronic pop],
      artist_country: 'BR',
      artist_official_url: 'https://www.alokmusic.com/'
    )

    assert_equal 'found', result.status
    assert result.found?
    assert_equal candidate.image_url, result.candidate.image_url
    assert_equal 'wikimedia_commons', result.candidate.provider
    assert_operator result.confidence, :>=, 90
    assert_equal '4646863', result.identifiers[:songkick_id]
    assert_equal ALOK_MBID, result.identifiers[:musicbrainz_id]
    assert_equal 'Q28007321', result.identifiers[:wikidata_id]
    assert_equal 3, result.provider_attempts.size
    assert_equal 5, coordinator.requests_count
    assert_equal 'CC BY 2.0', result.evidence.dig(:selected_candidate, :license, :name)
  end

  test 'rejects two different musicians with the same name as ambiguous' do
    first_musicbrainz = musicbrainz_identity(name: 'Alex', mbid: ALOK_MBID, qid: 'Q1001')
    second_musicbrainz = musicbrainz_identity(name: 'Alex', mbid: SECOND_MBID, qid: 'Q1002')
    first_wikidata = wikidata_identity(name: 'Alex', mbid: ALOK_MBID, qid: 'Q1001', genres: ['rock'])
    second_wikidata = wikidata_identity(name: 'Alex', mbid: SECOND_MBID, qid: 'Q1002', genres: ['rock'])
    providers = [
      FakeProvider.new('musicbrainz', provider_ok(identities: [first_musicbrainz, second_musicbrainz], requests_count: 3)),
      FakeProvider.new(
        'wikimedia_commons',
        provider_ok(
          candidates: [commons_candidate(identity: first_wikidata), commons_candidate(identity: second_wikidata)],
          requests_count: 1
        )
      )
    ]

    result = BlackCoffeeConcertCoverSearch::Coordinator.new(providers: providers).search(
      artist_name: 'Alex',
      genres: ['rock']
    )

    assert_equal 'ambiguous', result.status
    assert result.ambiguous?
    assert_nil result.candidate
    assert_equal 'ambiguous_artist_identity', result.error_type
    assert_equal 2, result.evidence.dig(:matcher, :ranked_candidates).count { |entry| entry[:safe] }
  end

  test 'does not publish an exact-name-only candidate' do
    identity = {
      provider: 'wikidata',
      name: 'Alex',
      aliases: [],
      genres: [],
      identifiers: { wikidata_id: 'Q4242' },
      evidence: { musical_entity: true }
    }
    provider = FakeProvider.new(
      'wikimedia_commons',
      provider_ok(candidates: [commons_candidate(identity: identity)], requests_count: 1)
    )

    result = BlackCoffeeConcertCoverSearch::Coordinator.new(providers: [provider]).search(artist_name: 'Alex')

    assert_equal 'ambiguous', result.status
    assert_nil result.candidate
    ranked = result.evidence.dig(:matcher, :ranked_candidates).first
    assert_equal false, ranked[:safe]
    assert_equal ['musical_entity_type'], ranked[:signals]
  end

  test 'does not publish a crosslinked homonym without corroboration from the event' do
    musicbrainz = musicbrainz_identity(name: 'Common Artist', mbid: ALOK_MBID, qid: 'Q4242')
    wikidata = wikidata_identity(
      name: 'Common Artist',
      mbid: ALOK_MBID,
      qid: 'Q4242',
      genres: ['electronic']
    )
    providers = [
      FakeProvider.new('musicbrainz', provider_ok(identities: [musicbrainz], requests_count: 1)),
      FakeProvider.new(
        'wikimedia_commons',
        provider_ok(candidates: [commons_candidate(identity: wikidata)], requests_count: 1)
      )
    ]

    result = BlackCoffeeConcertCoverSearch::Coordinator.new(providers: providers).search(
      artist_name: 'Common Artist'
    )

    assert_equal 'ambiguous', result.status
    assert_nil result.candidate
    signals = result.evidence.dig(:matcher, :ranked_candidates).first[:signals]
    assert_includes signals, 'musicbrainz_wikidata_crosslink'
    assert_includes signals, 'musicbrainz_qid_crosslink'
  end

  test 'returns retryable_error when an upstream provider is rate limited' do
    rate_limited = BlackCoffeeConcertCoverSearch::ProviderResult.failure(
      status: 'retryable_error',
      error_type: 'rate_limited',
      error_message: 'HTTP 429',
      evidence: { retry_after: 15 },
      requests_count: 1
    )
    not_found = BlackCoffeeConcertCoverSearch::ProviderResult.failure(
      status: 'not_found',
      error_type: 'commons_not_found',
      error_message: 'No image',
      requests_count: 1
    )
    coordinator = BlackCoffeeConcertCoverSearch::Coordinator.new(
      providers: [FakeProvider.new('musicbrainz', rate_limited), FakeProvider.new('wikimedia_commons', not_found)]
    )

    result = coordinator.search(artist_name: 'Alok')

    assert_equal 'retryable_error', result.status
    assert result.retryable?
    assert_equal 'rate_limited', result.error_type
    assert_equal 2, coordinator.requests_count
  end

  test 'continues safely when one provider is down and another has the Songkick crosslink' do
    unavailable = FakeProvider.new('musicbrainz') { raise SocketError, 'provider down' }
    identity = wikidata_identity(
      name: 'Alok',
      mbid: ALOK_MBID,
      qid: 'Q28007321',
      songkick_id: '4646863',
      genres: ['electronic']
    )
    wikidata = FakeProvider.new('wikidata', provider_ok(identities: [identity], requests_count: 1))
    commons = FakeProvider.new(
      'wikimedia_commons',
      provider_ok(candidates: [commons_candidate(identity: identity)], requests_count: 1)
    )
    coordinator = BlackCoffeeConcertCoverSearch::Coordinator.new(providers: [unavailable, wikidata, commons])

    result = coordinator.search(artist_name: 'Alok', songkick_artist_id: '4646863')

    assert_equal 'found', result.status
    assert_equal %w[unavailable ok ok], result.provider_attempts.map { |attempt| attempt[:status] }
    assert_includes result.evidence.dig(:matcher, :selected_signals), 'songkick_id_crosslink'
    assert_equal 2, coordinator.requests_count
  end

  private

  def provider_ok(identities: [], candidates: [], requests_count: 0)
    BlackCoffeeConcertCoverSearch::ProviderResult.ok(
      identities: identities,
      candidates: candidates,
      requests_count: requests_count
    )
  end

  def musicbrainz_identity(name:, mbid:, qid:, songkick_id: nil)
    {
      provider: 'musicbrainz',
      name: name,
      aliases: [],
      country: 'BR',
      genres: %w[electronic rock],
      official_urls: ['https://artist.example/'],
      identifiers: {
        musicbrainz_id: mbid,
        wikidata_id: qid,
        songkick_id: songkick_id
      }.compact,
      evidence: {}
    }
  end

  def wikidata_identity(name:, mbid:, qid:, songkick_id: nil, genres: [])
    {
      provider: 'wikidata',
      name: name,
      aliases: [],
      country: 'BR',
      countries: ['BR'],
      genres: genres,
      types: ['disc jockey'],
      official_urls: ['https://artist.example/'],
      image_file: "#{name}-#{qid}.jpg",
      identifiers: {
        musicbrainz_id: mbid,
        wikidata_id: qid,
        songkick_id: songkick_id
      }.compact,
      evidence: {
        musicbrainz_ids: [mbid],
        songkick_ids: Array(songkick_id),
        musical_entity: true
      }
    }
  end

  def commons_candidate(identity:)
    qid = identity.dig(:identifiers, :wikidata_id)
    BlackCoffeeConcertCoverSearch::Candidate.new(
      image_url: "https://upload.wikimedia.org/#{qid}.jpg",
      page_url: "https://commons.wikimedia.org/wiki/File:#{qid}.jpg",
      provider: 'wikimedia_commons',
      width: 1_200,
      height: 900,
      identifiers: identity[:identifiers],
      evidence: {
        identity: identity,
        license: {
          name: 'CC BY 2.0',
          url: 'https://creativecommons.org/licenses/by/2.0/',
          artist: 'Fixture photographer'
        }
      }
    )
  end
end
