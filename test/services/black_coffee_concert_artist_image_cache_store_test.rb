require 'stringio'
require 'test_helper'

class BlackCoffeeConcertArtistImageCacheStoreTest < ActiveSupport::TestCase
  FakeUploader = Struct.new(:file, :url)
  FakeVenueImage = Struct.new(:image) do
    def uploaded_image?
      true
    end
  end
  FakeRecord = Struct.new(
    :identity_key,
    :status,
    :venue_image,
    :image_content_type,
    :image_url,
    :source_page_url,
    :confidence,
    :evidence,
    :musicbrainz_id,
    :wikidata_id,
    keyword_init: true
  ) do
    def fresh?
      true
    end

    def resolved?
      status == 'resolved'
    end

    def reusable_binary?
      resolved? && venue_image&.uploaded_image?
    end
  end

  class FakeScope
    def initialize(record)
      @record = record
    end

    def find_by(identity_key:)
      @record if @record.identity_key == identity_key
    end
  end

  test 'uses the stable Songkick artist id instead of the display name' do
    store = BlackCoffeeConcertArtistImageCacheStore.new(available: false)

    first = store.identity_key_for(artist_name: 'Alok', source_artist_id: '4646863', genres: ['electronic'])
    second = store.identity_key_for(artist_name: 'A different spelling', source_artist_id: '4646863', genres: [])

    assert_equal 'songkick:4646863', first
    assert_equal first, second
  end

  test 'reuses verified stored bytes without another image request' do
    body = jpeg_bytes(width: 300, height: 300)
    uploader = FakeUploader.new(StringIO.new(body), '/uploads/concert-cover.jpg')
    record = FakeRecord.new(
      identity_key: 'songkick:4646863',
      status: 'resolved',
      venue_image: FakeVenueImage.new(uploader),
      image_content_type: 'image/jpeg',
      image_url: 'https://commons.wikimedia.org/alok.jpg',
      source_page_url: 'https://commons.wikimedia.org/wiki/File:Alok.jpg',
      confidence: 100,
      evidence: { identity_match: 'songkick_crosslink' },
      musicbrainz_id: '311dc522-c8c6-4114-9b6c-3ed0ed41316f',
      wikidata_id: 'Q28007321'
    )
    store = BlackCoffeeConcertArtistImageCacheStore.new(
      scope: FakeScope.new(record),
      inspector: BlackCoffeeImageInspector.new(validate_visual_content: false),
      available: true
    )

    lookup = store.lookup(artist_name: 'Alok', source_artist_id: '4646863', genres: ['electronic'])

    assert lookup.reusable?
    assert_equal body, lookup.download.body
    assert_equal 300, lookup.download.width
    assert_equal Digest::SHA256.hexdigest(body), lookup.download.sha256
  end

  test 'never reuses a positive cache entry identified only by a name' do
    record = FakeRecord.new(
      identity_key: "name:#{Digest::SHA256.hexdigest('common name|rock')}",
      status: 'resolved',
      evidence: {}
    )
    store = BlackCoffeeConcertArtistImageCacheStore.new(
      scope: FakeScope.new(record),
      available: true
    )

    lookup = store.lookup(artist_name: 'Common Name', genres: ['rock'])

    assert_nil lookup
  end

  private

  def jpeg_bytes(width:, height:)
    body = "\xFF\xD8\xFF\xC0".b
    body << [17].pack('n')
    body << [8].pack('C')
    body << [height, width].pack('n2')
    body << [3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0].pack('C*')
    body << "\xFF\xD9".b
    body
  end
end
