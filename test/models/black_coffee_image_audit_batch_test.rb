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
end
