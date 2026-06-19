require 'test_helper'

class FanMusicFestImporterTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:html, :robots_requests_count, :listing_requests_count, :detail_requests_count, :detail_html) do
    def fetch_calendar_page(page:)
      self.listing_requests_count += 1
      html
    end

    def fetch_detail(_url)
      self.detail_requests_count += 1
      detail_html
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
              "description": "Una descripcion del festival suficientemente extensa para quedar pendiente de revision editorial.",
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
    assert_equal 'https://fanmusicfest.com/content/valid-fest-2026', venue.external_source_url
    assert_equal 'schema_org', venue.coordinates_source
    assert_equal 'high', venue.coordinates_confidence
    assert_equal 'needs_review', venue.source_description_status
    assert_nil venue.festival_public_description
    assert_equal 'es', run.items.find_by(venue_id: venue.id).source_description_language
    assert_equal 'needs_review', run.items.find_by(venue_id: venue.id).source_description_status
  end

  test 'refresh details updates the existing festival without duplicating it' do
    venue = Venue.create!(
      name: 'Valid Fest',
      category: 'festival',
      description: 'Texto editado manualmente',
      address: 'Recinto Valid, Madrid',
      city: 'Madrid',
      latitude: 40.4168,
      longitude: -3.7038,
      featured: false,
      festival_start_date: Date.new(2026, 9, 1),
      festival_venue_name: 'Recinto corregido manualmente',
      external_source: 'fanmusicfest',
      external_source_url: 'https://fanmusicfest.com/content/valid-fest-2026',
      external_source_id: 'https://fanmusicfest.com/content/valid-fest-2026#event'
    )
    run = BlackCoffeeFestivalImportRun.create!(
      operation: 'refresh_details',
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 1,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: true,
      auto_publish: false,
      preserve_manual_edits: true
    )
    client = FakeClient.new(nil, 0, 0, 0, SAMPLE_HTML)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    assert_equal 1, Venue.where(category: 'festival').count
    assert_equal 1, run.reload.venues_updated_count
    assert_equal 'Texto editado manualmente', venue.reload.description
    assert_equal Date.new(2026, 9, 1), venue.festival_start_date
    assert_equal 'Recinto corregido manualmente', venue.festival_venue_name
    assert_equal 'needs_review', venue.source_description_status
    assert_match(/descripcion del festival/, venue.source_description)
  end
end
