require 'test_helper'

class BlackCoffeeImageInternalizationBatchTest < ActiveSupport::TestCase
  test 'reports progress from processed and total images' do
    batch = BlackCoffeeImageInternalizationBatch.new(processed_images: 25, total_images: 100)

    assert_equal 25, batch.progress_percentage
  end

  test 'labels statuses for dashboard display' do
    assert_equal 'Pendiente', BlackCoffeeImageInternalizationBatch.new(status: 'pending').status_label
    assert_equal 'Procesando', BlackCoffeeImageInternalizationBatch.new(status: 'running').status_label
    assert_equal 'Completado', BlackCoffeeImageInternalizationBatch.new(status: 'completed').status_label
    assert_equal 'Fallido', BlackCoffeeImageInternalizationBatch.new(status: 'failed').status_label
  end
end
