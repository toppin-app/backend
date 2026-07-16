require 'test_helper'
require 'minitest/mock'
require 'base64'
require 'fileutils'

class BlackCoffeeConcertCoverRepairRunnerTest < ActiveSupport::TestCase
  class FakeResolver
    attr_reader :result

    def initialize(result)
      @result = result
    end

    def resolve_for_venue(_venue)
      result
    end

    def source_total_requests_count
      0
    end

    def image_download_requests_count
      0
    end
  end

  class FakeAttacher
    attr_reader :calls

    def initialize(result: Object.new)
      @calls = []
      @result = result
    end

    def attach!(**attributes)
      calls << attributes
      @result
    end
  end

  setup do
    skip 'concert cover repair tables are not available in this test schema' unless repair_schema_available?

    BlackCoffeeConcertCoverRepairItem.delete_all
    BlackCoffeeConcertCoverRepairBatch.delete_all
    Venue.where(category: 'concierto').find_each(&:destroy!)
  end

  test 'moves a concert to hidden pending review when cover absence is confirmed' do
    venue = create_concert!
    batch = create_batch!
    missing = BlackCoffeeConcertCoverResolver::Result.new(
      status: 'missing',
      error_type: 'source_without_working_image',
      error_message: 'Songkick has no working image.'
    )

    advance!(batch, missing)

    venue.reload
    item = batch.items.first.reload
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status
    assert_nil venue.review_rejection_reason
    refute venue.visible
    assert_equal 'needs_review', item.status
    assert_equal 0, batch.reload.rejected_count
    assert_equal 1, batch.pending_review_count if batch.has_attribute?(:pending_review_count)
  end

  test 'hides a concert when a provider has a transient error and no persisted cover' do
    venue = create_concert!
    batch = create_batch!
    retryable = BlackCoffeeConcertCoverResolver::Result.new(
      status: 'retryable_error',
      error_type: 'source_request_error',
      error_message: 'Temporary Songkick outage.'
    )

    advance!(batch, retryable)

    venue.reload
    item = batch.items.first.reload
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status
    refute venue.visible
    assert_equal 'needs_review', item.status
    assert_match(/Temporary Songkick outage/, item.error_message)
  end

  test 'records a recovered binary cover without changing review status' do
    venue = create_concert!
    batch = create_batch!
    attacher = FakeAttacher.new
    recovered = BlackCoffeeConcertCoverResolver::Result.new(
      status: 'recovered',
      download: successful_download,
      resolution_source: 'source_page',
      image_url: 'https://images.example.test/concert.jpg',
      page_url: 'https://www.songkick.com/concerts/123-test-concert',
      confidence: 100,
      evidence: { date_match: true }
    )

    BlackCoffeeConcertCoverAttachment.stub(:verify_persisted!, Object.new) do
      BlackCoffeeConcertCoverRepairRunner.advance!(
        batch: batch,
        limit: 1,
        resolver: FakeResolver.new(recovered),
        attacher: attacher
      )
    end

    assert_equal Venue::REVIEW_STATUS_APPROVED, venue.reload.review_status
    assert_equal 'recovered_source', batch.items.first.reload.status
    assert_equal 1, attacher.calls.size
    assert_equal venue, attacher.calls.first[:venue]
  end

  test 'does not mark recovery successful when the attachment was not persisted' do
    venue = create_concert!
    batch = create_batch!
    recovered = BlackCoffeeConcertCoverResolver::Result.new(
      status: 'recovered',
      download: successful_download,
      resolution_source: 'source_page',
      image_url: 'https://images.example.test/concert.jpg',
      page_url: 'https://www.songkick.com/concerts/123-test-concert'
    )

    BlackCoffeeConcertCoverRepairRunner.advance!(
      batch: batch,
      limit: 1,
      resolver: FakeResolver.new(recovered),
      attacher: FakeAttacher.new(result: nil)
    )

    venue.reload
    item = batch.items.first.reload
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status
    refute venue.visible
    assert_equal 'needs_review', item.status
    assert_equal 'cover_attachment_failed', item.error_type
  end

  test 'includes concerts with external covers so their URLs are internalized' do
    venue = create_concert!
    venue.venue_images.create!(
      position: 0,
      url: 'https://images.example.test/existing-cover.jpg'
    )

    inventory = BlackCoffeeConcertCoverRepairRunner.cover_inventory(review_status_filter: 'approved')
    batch = create_batch!

    assert_equal 1, inventory[:total]
    assert_equal 0, inventory[:binary]
    assert_equal 1, inventory[:external]
    assert_equal 0, inventory[:without_url]
    assert_equal 1, inventory[:pending_internalization]
    assert_equal 1, batch.total_venues
  end

  test 'includes concerts without any image source so Songkick can be retried' do
    create_concert!

    inventory = BlackCoffeeConcertCoverRepairRunner.cover_inventory(review_status_filter: 'approved')
    batch = create_batch!

    assert_equal 0, inventory[:external]
    assert_equal 1, inventory[:without_url]
    assert_equal 1, inventory[:pending_internalization]
    assert_equal 1, batch.total_venues
  end

  test 'never replaces an existing uploaded cover with a newly searched image' do
    venue = create_concert!
    image = venue.venue_images.create!(
      position: 0,
      url: 'https://images.example.test/original-manual-cover.jpg'
    )
    image.update_columns(image: 'manual-cover.jpg', url: nil)

    inventory = BlackCoffeeConcertCoverRepairRunner.cover_inventory(review_status_filter: 'approved')
    batch = create_batch!

    assert_equal 1, inventory[:binary]
    assert_equal 0, inventory[:pending_internalization]
    assert_equal 1, batch.total_venues

    missing = BlackCoffeeConcertCoverResolver::Result.new(status: 'missing', error_message: 'Should not be used')
    BlackCoffeeConcertCoverAttachment.stub(:usable_persisted_binary, image) do
      advance!(batch, missing)
    end

    assert_equal Venue::REVIEW_STATUS_APPROVED, venue.reload.review_status
    assert venue.visible
    assert_equal 'skipped', batch.items.first.reload.status
    assert_equal 'cover_already_present', batch.items.first.error_type
    assert_equal 'manual-cover.jpg', image.reload[:image]
  end

  test 'promotes a usable stored cover ahead of an unusable primary reference' do
    venue = create_concert!
    broken_primary = venue.venue_images.create!(
      position: 0,
      url: 'https://images.example.test/broken-primary.jpg'
    )
    usable_secondary = venue.venue_images.create!(
      position: 1,
      url: 'https://images.example.test/temporary-source.jpg'
    )
    usable_secondary.update_columns(image: 'usable-secondary.jpg', url: nil)
    batch = create_batch!
    missing = BlackCoffeeConcertCoverResolver::Result.new(status: 'missing', error_message: 'Should not be used')

    verifier = lambda do |venue:, venue_image:|
      venue_image if venue_image.id == usable_secondary.id
    end
    BlackCoffeeConcertCoverAttachment.stub(:usable_persisted_binary, verifier) do
      advance!(batch, missing)
    end

    assert_equal 0, usable_secondary.reload.position
    assert_equal 1, broken_primary.reload.position
    assert_equal 'skipped', batch.items.first.reload.status
    assert_equal Venue::REVIEW_STATUS_APPROVED, venue.reload.review_status
    assert venue.visible
  end

  test 'includes an importer managed binary whose stored object is missing' do
    venue = create_concert!
    image = venue.venue_images.create!(
      position: 0,
      url: 'https://images.example.test/original-cover.jpg',
      source: 'concert_cover_source_page'
    )
    image.update_columns(image: 'missing-from-storage.jpg', url: nil)

    batch = create_batch!

    assert_equal 1, batch.total_venues
    assert_equal venue.id, batch.items.first.venue_id
  end

  test 'moves a previously approved concert with the exact transparent Songkick PNG to pending' do
    venue = create_concert!
    body = Base64.strict_decode64(
      'iVBORw0KGgoAAAANSUhEUgAAASwAAAEsAQAAAABRBrPYAAAAAnRSTlMAAQGU/a4AAABASURBVHgB7cpBAQBABACwu/5pJSACvLf3fr6B0DRN0zRN0zRN0zRN0zTt0DRN0zRN0zRN0zRN0zRN0zRN0zStAMAZRou3pllOAAAAAElFTkSuQmCC'
    )
    image = stored_image!(venue, filename: 'jpfernandez-transparent.png', body: body)
    batch = create_batch!
    missing = BlackCoffeeConcertCoverResolver::Result.new(
      status: 'missing',
      error_type: 'source_without_working_image',
      error_message: 'No alternative cover found.'
    )

    advance!(batch, missing)

    venue.reload
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status
    refute venue.visible
    assert_equal 'needs_review', batch.items.first.reload.status
    assert_nil BlackCoffeeConcertCoverAttachment.usable_persisted_binary(
      venue: venue,
      venue_image: image.reload
    )
  end

  private

  def repair_schema_available?
    connection = ActiveRecord::Base.connection
    connection.data_source_exists?('black_coffee_concert_cover_repair_batches') &&
      connection.data_source_exists?('black_coffee_concert_cover_repair_items')
  end

  def create_concert!
    Venue.create!(
      name: 'Test Concert',
      category: 'concierto',
      address: 'Test Venue, Madrid',
      city: 'Madrid',
      latitude: 40.416775,
      longitude: -3.703790,
      review_status: Venue::REVIEW_STATUS_APPROVED,
      visible: true,
      featured: false,
      event_status: Venue::EVENT_STATUS_UPCOMING,
      event_start_at: 2.months.from_now,
      festival_start_date: 2.months.from_now.to_date,
      external_source: SongkickConcerts::Normalizer::SOURCE,
      external_source_url: 'https://www.songkick.com/concerts/123-test-concert',
      external_source_id: '123'
    )
  end

  def create_batch!
    BlackCoffeeConcertCoverRepairRunner.create_batch!(
      created_by: nil,
      review_status_filter: 'approved'
    )
  end

  def advance!(batch, result)
    BlackCoffeeConcertCoverRepairRunner.advance!(
      batch: batch,
      limit: 1,
      resolver: FakeResolver.new(result),
      attacher: FakeAttacher.new
    )
  end

  def successful_download
    BlackCoffeeImageDownloader::DownloadResult.new(
      ok?: true,
      body: 'image-bytes',
      content_type: 'image/jpeg',
      extension: 'jpg',
      http_status: 200
    )
  end

  def stored_image!(venue, filename:, body:)
    image = venue.venue_images.create!(
      position: 0,
      url: 'https://images.example.test/temporary-source',
      source: 'concert_cover_source_page'
    )
    image.update_columns(image: filename, url: nil)
    image.reload
    FileUtils.mkdir_p(File.dirname(image.image.path))
    File.binwrite(image.image.path, body)
    image
  end
end
