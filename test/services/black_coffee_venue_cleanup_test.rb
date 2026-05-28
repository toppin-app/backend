require 'test_helper'
require 'minitest/mock'
require 'ostruct'

class BlackCoffeeVenueCleanupTest < ActiveSupport::TestCase
  FakeScope = Struct.new(:ids) do
    def pluck(column)
      raise "Unexpected pluck column: #{column}" unless column == :id

      ids
    end
  end

  FakeUpdateScope = Struct.new(:updates) do
    def update_all(attributes)
      updates << attributes
      updates.size
    end
  end

  test 'defaults to destructive delete operation and normalizes invalid params safely' do
    cleanup = BlackCoffeeVenueCleanup.new(
      operation: 'unexpected',
      category: 'not_a_category',
      source: 'invalid_source',
      visibility: 'invalid_visibility',
      review_rejection_reason: 'not_a_reason',
      review_rejection_note: '  nota interna  '
    )

    assert cleanup.delete_operation?
    refute cleanup.reject_operation?
    assert_nil cleanup.category
    assert_equal 'all', cleanup.source
    assert_equal 'all', cleanup.visibility
    assert_equal Venue::REJECTION_REASON_CODES.first, cleanup.review_rejection_reason
    assert_equal 'nota interna', cleanup.review_rejection_note
  end

  test 'supports non destructive reject operation with review metadata' do
    cleanup = BlackCoffeeVenueCleanup.new(
      operation: BlackCoffeeVenueCleanup::OPERATION_REJECT,
      category: 'cafeteria',
      source: 'google',
      visibility: 'visible',
      google_tag: ' Coffee Shop ',
      google_primary_type: ' Cafe ',
      review_rejection_reason: 'bad_photos',
      review_rejection_note: '  fotos inutilizables  '
    )

    assert cleanup.reject_operation?
    refute cleanup.delete_operation?
    assert_equal 'cafeteria', cleanup.category
    assert_equal 'google', cleanup.source
    assert_equal 'visible', cleanup.visibility
    assert_equal 'coffee_shop', cleanup.google_tag
    assert_equal 'cafe', cleanup.google_primary_type
    assert_equal 'bad_photos', cleanup.review_rejection_reason
    assert_equal 'fotos inutilizables', cleanup.review_rejection_note
    assert_equal 'bad_photos', cleanup.filters[:review_rejection_reason]
  end

  test 'reject updates only selected venues and does not call destroy flow' do
    cleanup = BlackCoffeeVenueCleanup.new(
      operation: BlackCoffeeVenueCleanup::OPERATION_REJECT,
      review_rejection_reason: 'not_interesting',
      review_rejection_note: 'fuera de criterio editorial'
    )
    fixed_time = Time.zone.parse('2026-05-28 12:00:00')
    reviewer = OpenStruct.new(id: 42)
    updates = []
    where_filters = []

    cleanup.define_singleton_method(:scope) { FakeScope.new([10, 20, 30]) }
    cleanup.define_singleton_method(:has_venue_column?) do |column_name|
      %w[review_status reviewed_by_id featured].include?(column_name.to_s)
    end

    transaction = ->(&block) { block.call }
    where = lambda do |filters|
      where_filters << filters
      FakeUpdateScope.new(updates)
    end

    ActiveRecord::Base.stub(:transaction, transaction) do
      Time.stub(:current, fixed_time) do
        Venue.stub(:where, where) do
          result = cleanup.reject!(reviewed_by: reviewer)

          assert_equal 3, result[:rejected_count]
          assert_equal 3, result[:rejected_ids_count]
          assert_equal 'not_interesting', result[:review_rejection_reason]
          assert result[:review_rejection_note_present]
        end
      end
    end

    assert_equal [{ id: [10, 20, 30] }], where_filters
    assert_equal 1, updates.size
    assert_equal(
      {
        review_status: Venue::REVIEW_STATUS_REJECTED,
        review_rejection_reason: 'not_interesting',
        review_rejection_note: 'fuera de criterio editorial',
        reviewed_at: fixed_time,
        updated_at: fixed_time,
        reviewed_by_id: 42,
        featured: false
      },
      updates.first
    )
  end

  test 'reject fails clearly when review status is not available' do
    cleanup = BlackCoffeeVenueCleanup.new(operation: BlackCoffeeVenueCleanup::OPERATION_REJECT)
    cleanup.define_singleton_method(:has_venue_column?) { |_column_name| false }

    error = assert_raises(RuntimeError) { cleanup.reject! }

    assert_equal 'Esta instalacion no tiene columna review_status en locales.', error.message
  end
end
