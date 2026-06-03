require 'test_helper'

class BlackCoffeeImageInternalizationRunnerTest < ActiveSupport::TestCase
  class RaisingDownloader
    def download(_url)
      raise RuntimeError, 'boom'
    end
  end

  test 'keeps processing state consistent when one image raises unexpectedly' do
    venue = Venue.create!(
      name: 'Runner Test Cafe',
      category: 'cafeteria',
      address: 'Calle Test 1',
      city: 'Valencia',
      latitude: 39.4699,
      longitude: -0.3763
    )
    venue_image = venue.venue_images.create!(url: 'https://cdn.toppin.test/broken.jpg', position: 0)
    batch = BlackCoffeeImageInternalizationBatch.create!(
      status: 'pending',
      total_venues: 1,
      total_images: 1
    )
    item = batch.items.create!(
      venue: venue,
      venue_image: venue_image,
      source_url: venue_image.url,
      status: 'pending'
    )

    BlackCoffeeImageInternalizationRunner.advance!(
      batch: batch,
      downloader: RaisingDownloader.new,
      limit: 1
    )

    batch.reload
    item.reload
    assert_equal 'completed', batch.status
    assert_equal 1, batch.processed_images
    assert_equal 1, batch.failed_images_count
    assert_equal 'failed', item.status
    assert_equal 'unexpected_item_error', item.error_type
    assert_match 'RuntimeError - boom', item.error_message
  end
end
