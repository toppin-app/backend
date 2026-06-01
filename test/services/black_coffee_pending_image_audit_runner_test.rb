require 'test_helper'
require 'ostruct'

class BlackCoffeePendingImageAuditRunnerTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :headers) do
    def [](key)
      headers.to_h[key.to_s.downcase]
    end
  end

  FakeBatch = Struct.new(:id, :updates) do
    def items
      OpenStruct.new(pending: OpenStruct.new(exists?: false))
    end

    def failed_venue_ids
      %w[ven_1 ven_2]
    end

    def update!(attributes)
      updates << attributes
    end
  end

  FakeVenueUpdateScope = Struct.new(:updates) do
    def update_all(attributes)
      updates << attributes
      2
    end
  end

  PendingBatch = Struct.new(:id) do
    def items
      OpenStruct.new(pending: OpenStruct.new(exists?: true))
    end
  end

  test 'image checker accepts successful image responses' do
    checker = BlackCoffeePendingImageAuditRunner::ImageChecker.new
    checker.define_singleton_method(:request_with_redirects) do |_uri|
      FakeResponse.new('200', { 'content-type' => 'image/jpeg' })
    end

    result = checker.check('https://example.com/image.jpg')

    assert_equal 'ok', result.status
    assert_equal 200, result.http_status
    assert_nil result.error_type
  end

  test 'image checker rejects successful non image responses' do
    checker = BlackCoffeePendingImageAuditRunner::ImageChecker.new
    checker.define_singleton_method(:request_with_redirects) do |_uri|
      FakeResponse.new('200', { 'content-type' => 'text/html' })
    end

    result = checker.check('https://example.com/not-image')

    assert_equal 'failed', result.status
    assert_equal 'not_image', result.error_type
    assert_equal 200, result.http_status
  end

  test 'image checker rejects blank and invalid urls without network calls' do
    checker = BlackCoffeePendingImageAuditRunner::ImageChecker.new

    blank_result = checker.check('')
    invalid_result = checker.check('ftp://example.com/image.jpg')

    assert_equal 'failed', blank_result.status
    assert_equal 'missing_image', blank_result.error_type
    assert_equal 'failed', invalid_result.status
    assert_equal 'invalid_url', invalid_result.error_type
  end

  test 'reject_failed marks only pending failed venues as bad photos' do
    batch = FakeBatch.new(7, [])
    runner = BlackCoffeePendingImageAuditRunner.new(batch: batch)
    runner.define_singleton_method(:refresh_counts!) { |audit_batch| audit_batch }

    fixed_time = Time.zone.parse('2026-06-01 10:00:00')
    reviewer = OpenStruct.new(id: 101)
    where_filters = []
    venue_updates = []

    transaction = ->(&block) { block.call }
    where = lambda do |filters|
      where_filters << filters
      FakeVenueUpdateScope.new(venue_updates)
    end

    BlackCoffeeImageAuditBatch.stub(:transaction, transaction) do
      Time.stub(:current, fixed_time) do
        Venue.stub(:where, where) do
          rejected_count = runner.reject_failed!(reviewer: reviewer)

          assert_equal 2, rejected_count
        end
      end
    end

    assert_equal(
      [{ id: %w[ven_1 ven_2], review_status: Venue::REVIEW_STATUS_PENDING }],
      where_filters
    )
    assert_equal 1, venue_updates.size
    assert_equal Venue::REVIEW_STATUS_REJECTED, venue_updates.first[:review_status]
    assert_equal 'bad_photos', venue_updates.first[:review_rejection_reason]
    assert_includes venue_updates.first[:review_rejection_note], 'auditoria de imagenes Black Coffee #7'
    assert_equal fixed_time, venue_updates.first[:reviewed_at]
    assert_equal 101, venue_updates.first[:reviewed_by_id]
    assert_equal fixed_time, venue_updates.first[:updated_at]
    assert_equal 1, batch.updates.size
    assert_equal 'rejected', batch.updates.first[:status]
    assert_equal 2, batch.updates.first[:rejected_venues_count]
    assert_equal 101, batch.updates.first[:rejected_by_id]
  end

  test 'reject_failed refuses to apply before all image checks are done' do
    runner = BlackCoffeePendingImageAuditRunner.new(batch: PendingBatch.new(8))

    error = assert_raises(ArgumentError) do
      runner.reject_failed!(reviewer: nil)
    end

    assert_includes error.message, 'Termina de procesar todas las imagenes'
  end
end
