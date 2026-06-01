require 'test_helper'

class VenueImageTest < ActiveSupport::TestCase
  TEMPORARY_GOOGLE_PHOTO_URL = 'https://lh3.googleusercontent.com/place-photos/AJRVUZExample=s4800-w1200'.freeze

  test 'detects temporary Google Places photo urls' do
    assert VenueImage.temporary_google_place_photo_url?(TEMPORARY_GOOGLE_PHOTO_URL)
    assert VenueImage.temporary_google_place_photo_url?("  #{TEMPORARY_GOOGLE_PHOTO_URL}  ")
    assert_not VenueImage.temporary_google_place_photo_url?('https://example.com/place-photos/AJRVUZExample=s4800-w1200')
    assert_not VenueImage.temporary_google_place_photo_url?('https://lh3.googleusercontent.com/a-/profile-photo=s100')
  end

  test 'public url hides temporary Google Places photo urls' do
    image = VenueImage.new(url: TEMPORARY_GOOGLE_PHOTO_URL)

    assert_nil image.public_url(base_url: 'https://api.toppin.test')
  end

  test 'public url still exposes normal external images' do
    image = VenueImage.new(url: 'https://cdn.toppin.test/black-coffee/place.jpg')

    assert_equal 'https://cdn.toppin.test/black-coffee/place.jpg', image.public_url(base_url: 'https://api.toppin.test')
  end
end
