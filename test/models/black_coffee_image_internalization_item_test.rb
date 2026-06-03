require 'test_helper'

class BlackCoffeeImageInternalizationItemTest < ActiveSupport::TestCase
  test 'returns friendly labels for known error types' do
    item = BlackCoffeeImageInternalizationItem.new(error_type: 'temporary_google_photo_uri')

    assert_equal 'URL temporal de Google Places', item.error_type_label
  end

  test 'falls back to raw error type when it is unknown' do
    item = BlackCoffeeImageInternalizationItem.new(error_type: 'provider_weird_error')

    assert_equal 'provider_weird_error', item.error_type_label
  end
end
