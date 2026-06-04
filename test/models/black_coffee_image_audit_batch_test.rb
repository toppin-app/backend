require 'test_helper'

class BlackCoffeeImageAuditBatchTest < ActiveSupport::TestCase
  test 'cancelled audit batches are valid finished processes' do
    batch = BlackCoffeeImageAuditBatch.new(status: 'cancelled')

    assert batch.valid?
    assert batch.cancelled?
    assert batch.finished?
    assert_equal 'Cancelado', batch.status_label
    assert_equal 'secondary', batch.status_badge_class
  end

  test 'audit batches expose review status filter labels' do
    batch = BlackCoffeeImageAuditBatch.new(
      status: 'pending',
      review_status_filter: Venue::REVIEW_STATUS_REJECTED
    )

    assert batch.valid?
    assert_equal 'Rechazados', batch.review_status_filter_label
    assert_includes BlackCoffeeImageAuditBatch.review_status_filter_options, ['Todos', 'all']
  end

  test 'audit batches expose server processing state' do
    batch = BlackCoffeeImageAuditBatch.new(
      status: 'running',
      processing_mode: 'server',
      total_images: 10,
      checked_images: 3
    )
    batch.define_singleton_method(:pending_checks?) { true }

    assert batch.server_processing?
    assert_equal 'Servidor', batch.processing_mode_label
  end
end
