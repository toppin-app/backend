require 'test_helper'
require 'minitest/mock'

class BlackCoffeeConcertCoverAttachmentTest < ActiveSupport::TestCase
  FakeVenue = Struct.new(:id, :venue_images)

  class FakeAssociation
    attr_reader :images

    def initialize(images)
      @images = images
    end

    def to_a
      images
    end

    def create!(attributes)
      image = FakeImage.new(id: images.size + 1, **attributes)
      images << image
      image
    end
  end

  class FakeImage
    attr_accessor :id, :url, :source, :position, :author_attributions, :assigned_image

    def initialize(id:, url:, source: nil, position: 0)
      @id = id
      @url = url
      @source = source
      @position = position
    end

    def uploaded_image?
      false
    end

    def image=(value)
      @assigned_image = value
    end

    def save!
      @saved = true
    end

    def saved?
      @saved == true
    end
  end

  test 'internalizes an unusable external cover in its original primary slot' do
    external = FakeImage.new(
      id: 12,
      url: 'https://images.example.test/concert.jpg',
      source: 'songkick',
      position: 0
    )
    venue = FakeVenue.new('ven_test', FakeAssociation.new([external]))
    download = BlackCoffeeImageDownloader::DownloadResult.new(
      ok?: true,
      body: 'downloaded-image-bytes',
      content_type: 'image/jpeg',
      extension: 'jpg',
      http_status: 200
    )

    verifier = lambda do |venue:, venue_image:|
      venue_image
    end
    result = BlackCoffeeConcertCoverAttachment.stub(:verify_persisted!, verifier) do
      BlackCoffeeConcertCoverAttachment.attach!(
        venue: venue,
        download: download,
        resolution_source: 'source_metadata',
        source_url: external.url,
        provenance: { original_image_url: external.url }
      )
    end

    assert_equal external, result
    assert_equal 1, venue.venue_images.images.size
    assert external.saved?
    assert_nil external.url
    assert_equal 'concert_cover_source_metadata', external.source
    assert_equal 0, external.position
    assert_equal 'downloaded-image-bytes', external.assigned_image.read
    assert_match(/black_coffee_concert_cover_ven_test_12\.jpg/, external.assigned_image.original_filename)
    assert external.author_attributions['stored_as_binary_at'].present?
  end

  test 'rejects a missing or non VenueImage attachment as unpersisted' do
    error = assert_raises(BlackCoffeeConcertCoverAttachment::PersistenceError) do
      BlackCoffeeConcertCoverAttachment.verify_persisted!(
        venue: FakeVenue.new('ven_test', FakeAssociation.new([])),
        venue_image: nil
      )
    end

    assert_match(/no quedo persistida/, error.message)
  end
end
