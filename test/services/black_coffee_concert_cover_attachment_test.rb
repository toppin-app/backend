require 'test_helper'

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

  test 'downloads into the binary field and removes the external URL' do
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

    result = BlackCoffeeConcertCoverAttachment.attach!(
      venue: venue,
      download: download,
      resolution_source: 'source_metadata',
      source_url: external.url,
      provenance: { original_image_url: external.url }
    )

    assert_equal external, result

    assert external.saved?
    assert_nil external.url
    assert_equal 'concert_cover_source_metadata', external.source
    assert_equal 0, external.position
    assert_equal 'downloaded-image-bytes', external.assigned_image.read
    assert_match(/black_coffee_concert_cover_ven_test_12\.jpg/, external.assigned_image.original_filename)
    assert external.author_attributions['stored_as_binary_at'].present?
  end
end
