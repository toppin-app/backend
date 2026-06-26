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

  # Records which image URLs the importer tries to download. Always reports a
  # failure so the VenueImage keeps its URL and no real CarrierWave/MiniMagick
  # processing runs (ImageMagick is not available in the test environment).
  class RecordingDownloader
    attr_reader :requested_urls

    def initialize
      @requested_urls = []
    end

    def download(url)
      @requested_urls << url
      BlackCoffeeImageDownloader::DownloadResult.new(
        ok?: false,
        error_type: 'http_error',
        error_message: 'La imagen responde HTTP 403.',
        http_status: 403
      )
    end
  end

  def past_festival_html
    last_year = Date.current.prev_year.year
    <<~HTML
      <html>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Festival",
            "@id": "https://fanmusicfest.com/content/past-fest#event",
            "name": "Past Fest #{last_year} | Cartel",
            "url": "https://fanmusicfest.com/content/past-fest",
            "startDate": "#{last_year}-08-01",
            "endDate": "#{last_year}-08-03",
            "organizer": { "name": "Past Fest" },
            "location": {
              "address": {
                "addressLocality": "Sevilla",
                "addressRegion": "Sevilla",
                "addressCountry": "Espana"
              }
            }
          }
        </script>
      </html>
    HTML
  end

  # Past festival that only carries a startDate (no endDate) so the past_event?
  # fallback to start_date is exercised.
  def past_start_only_html
    last_year = Date.current.prev_year.year
    <<~HTML
      <html>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Festival",
            "@id": "https://fanmusicfest.com/content/past-start-only#event",
            "name": "Past Start Fest #{last_year} | Cartel",
            "url": "https://fanmusicfest.com/content/past-start-only",
            "startDate": "#{last_year}-08-01",
            "organizer": { "name": "Past Start Fest" },
            "location": {
              "address": {
                "addressLocality": "Sevilla",
                "addressRegion": "Sevilla",
                "addressCountry": "Espana"
              }
            }
          }
        </script>
      </html>
    HTML
  end

  # Spanish festival with no dates at all: must be kept for human review even when
  # only_future is enabled, because we cannot positively confirm it is in the past.
  def undated_spanish_html
    <<~HTML
      <html>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Festival",
            "@id": "https://fanmusicfest.com/content/undated-fest#event",
            "name": "Undated Fest | Cartel",
            "url": "https://fanmusicfest.com/content/undated-fest",
            "organizer": { "name": "Undated Fest" },
            "location": {
              "address": {
                "addressLocality": "Bilbao",
                "addressRegion": "Bizkaia",
                "addressCountry": "Espana"
              }
            }
          }
        </script>
      </html>
    HTML
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
      download_images: false,
      only_future: false,
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

  test 'import creates Spanish festivals as pending but visible venues' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: false,
      only_future: false,
      auto_publish: false
    )
    client = FakeClient.new(SAMPLE_HTML, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    venue = Venue.where(category: 'festival').find_by(name: 'Valid Fest')
    assert venue
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status if venue.has_attribute?(:review_status)
    assert_equal true, venue.visible if venue.has_attribute?(:visible)
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

  test 'skips past festivals when only_future is enabled' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: false,
      only_future: true,
      auto_publish: false
    )
    client = FakeClient.new(past_festival_html, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    run.reload
    assert_equal 0, Venue.where(category: 'festival').count
    assert_equal 1, run.past_skipped_count
    assert_equal 1, run.items.count
    assert_equal 1, run.items.where(status: 'skipped_past').count
  end

  test 'keeps past festivals when only_future is disabled' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: false,
      only_future: false,
      auto_publish: false
    )
    client = FakeClient.new(past_festival_html, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    run.reload
    assert_equal 0, run.past_skipped_count
    assert_equal 1, Venue.where(category: 'festival').count
  end

  test 'skips past festivals that only carry a start date' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: false,
      only_future: true,
      auto_publish: false
    )
    client = FakeClient.new(past_start_only_html, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    run.reload
    assert_equal 0, Venue.where(category: 'festival').count
    assert_equal 1, run.past_skipped_count
    assert_equal 1, run.items.where(status: 'skipped_past').count
  end

  test 'keeps undated festivals for review even when only_future is enabled' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: false,
      only_future: true,
      auto_publish: false
    )
    client = FakeClient.new(undated_spanish_html, 0, 0, 0)

    FanMusicFest::Importer.new(run: run, client: client).perform!

    run.reload
    assert_equal 0, run.past_skipped_count
    assert_equal 1, Venue.where(category: 'festival').count
    assert Venue.where(category: 'festival').exists?(name: 'Undated Fest')
  end

  test 'downloads the festival image as binary when download_images is enabled' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: true,
      only_future: false,
      auto_publish: false
    )
    client = FakeClient.new(SAMPLE_HTML, 0, 0, 0)
    downloader = RecordingDownloader.new

    FanMusicFest::Importer.new(run: run, client: client, image_downloader: downloader).perform!

    venue = Venue.where(category: 'festival').find_by(name: 'Valid Fest')
    assert venue
    # The importer attempted to internalize the candidate image as a binary file.
    assert_includes downloader.requested_urls, 'https://fanmusicfest.com/sites/default/files/valid.png'
    # The download failed in this test, so the URL is preserved as a fallback.
    assert_equal 'https://fanmusicfest.com/sites/default/files/valid.png', venue.venue_images.first.url
  end

  test 'does not download images when download_images is disabled' do
    run = BlackCoffeeFestivalImportRun.create!(
      mode: 'import',
      status: 'pending',
      max_pages: 1,
      max_details: 0,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      import_details: false,
      download_images: false,
      only_future: false,
      auto_publish: false
    )
    client = FakeClient.new(SAMPLE_HTML, 0, 0, 0)
    downloader = RecordingDownloader.new

    FanMusicFest::Importer.new(run: run, client: client, image_downloader: downloader).perform!

    venue = Venue.where(category: 'festival').find_by(name: 'Valid Fest')
    assert venue
    assert_empty downloader.requested_urls
    assert_equal 'https://fanmusicfest.com/sites/default/files/valid.png', venue.venue_images.first.url
  end
end
