require 'test_helper'

class FanMusicFestImporterTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:html, :robots_requests_count, :listing_requests_count, :detail_requests_count) do
    def fetch_calendar_page(page:)
      self.listing_requests_count += 1
      html
    end
  end

  SAMPLE_HTML = <<~HTML
    <html>
      <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "Festival",
              "@id": "https://fanmusicfest.com/content/valid-fest-2026#event",
              "name": "Valid Fest 2026 | Cartel",
              "url": "https://fanmusicfest.com/content/valid-fest-2026",
              "startDate": "2026-08-01",
              "endDate": "2026-08-03",
              "image": { "url": "https://fanmusicfest.com/sites/default/files/valid.png" },
              "organizer": { "name": "Valid Fest" },
              "location": {
                "name": "Recinto Valid",
                "address": {
                  "addressLocality": "Madrid",
                  "addressRegion": "Madrid",
                  "addressCountry": "Espana"
                },
                "geo": { "latitude": "40.4168", "longitude": "-3.7038" }
              }
            },
            {
              "@type": "Festival",
              "@id": "https://fanmusicfest.com/content/outside-fest-2026#event",
              "name": "Outside Fest 2026 | Cartel",
              "url": "https://fanmusicfest.com/content/outside-fest-2026",
              "location": {
                "address": {
                  "addressLocality": "Lisboa",
                  "addressCountry": "Portugal"
                },
                "geo": { "latitude": "38.7223", "longitude": "-9.1393" }
              }
            }
          ]
        }
      </script>
    </html>
  HTML

  setup do
    BlackCoffeeFestivalImportItem.delete_all if defined?(BlackCoffeeFestivalImportItem)
    festival_ids = Venue.where(category: 'festival').pluck(:id)
    VenueImage.where(venue_id: festival_ids).delete_all if festival_ids.any?
    Venue.where(id: festival_ids).delete_all if festival_ids.any?
    BlackCoffeeFestivalImportRun.delete_all
  end

  test 'dry run stores candidates without creating venues' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'dry_run',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      auto_publish: false
    )
    client = FakeClient.new(SAMPLE_HTML, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    run.reload
    assert_equal 'completed', run.status
    assert_equal 2, run.candidates_found_count
    assert_equal 1, run.outside_country_skipped_count
    assert_equal 1, run.needs_review_count
    assert_equal 0, run.venues_created_count
    assert_equal 0, Venue.where(category: 'festival').count
  end

  test 'import creates Spanish festivals as pending and hidden venues' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      auto_publish: false
    )
    client = FakeClient.new(SAMPLE_HTML, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    venue = Venue.where(category: 'festival').find_by(name: 'Valid Fest')
    assert venue
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status if venue.has_attribute?(:review_status)
    assert_equal false, venue.visible if venue.has_attribute?(:visible)
    assert_equal 1, venue.venue_images.count
    assert_equal 'https://fanmusicfest.com/sites/default/files/valid.png', venue.venue_images.first.url
  end
end
