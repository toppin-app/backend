require 'test_helper'

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

    def initialize
      @calls = []
    end

    def attach!(**attributes)
      calls << attributes
    end
  end

  setup do
    skip 'concert cover repair tables are not available in this test schema' unless repair_schema_available?

    BlackCoffeeConcertCoverRepairItem.delete_all
    BlackCoffeeConcertCoverRepairBatch.delete_all
    Venue.where(category: 'concierto').find_each(&:destroy!)
  end

  test 'rejects and hides a concert only after cover absence is confirmed' do
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
    assert_equal Venue::REVIEW_STATUS_REJECTED, venue.review_status
    assert_equal 'bad_photos', venue.review_rejection_reason
    refute venue.visible
    assert_equal 'rejected', item.status
    assert_equal 1, batch.reload.rejected_count
  end

  test 'does not reject a concert when a provider has a transient error' do
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
    assert_equal Venue::REVIEW_STATUS_APPROVED, venue.review_status
    assert venue.visible
    assert_equal 'failed', item.status
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

    BlackCoffeeConcertCoverRepairRunner.advance!(
      batch: batch,
      limit: 1,
      resolver: FakeResolver.new(recovered),
      attacher: attacher
    )

    assert_equal Venue::REVIEW_STATUS_APPROVED, venue.reload.review_status
    assert_equal 'recovered_source', batch.items.first.reload.status
    assert_equal 1, attacher.calls.size
    assert_equal venue, attacher.calls.first[:venue]
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
end
