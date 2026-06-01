require 'test_helper'

class VenueBlackCoffeeImagesTest < ActiveSupport::TestCase
  test 'stable image urls reject temporary Google Places photo urls' do
    temporary_url = 'https://lh3.googleusercontent.com/place-photos/AJRVUZExample=s4800-w1200'
    stable_url = 'https://cdn.toppin.test/black-coffee/place.jpg'

    assert_equal [stable_url], Venue.stable_black_coffee_image_urls([
      '',
      temporary_url,
      stable_url,
      stable_url
    ])
  end
end
