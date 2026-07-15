require 'test_helper'

class SongkickConcertsImporterTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:html, :robots_requests_count, :listing_requests_count, :detail_requests_count) do
    def fetch_metro_page(_path, page:)
      self.listing_requests_count += 1
      html
    end
  end

  setup do
    skip 'concert importer columns are not available in this test schema' unless required_columns_present?

    BlackCoffeeConcertImportItem.delete_all
    BlackCoffeeConcertImportRun.delete_all
    Venue.where(category: 'concierto').find_each(&:destroy!)
  end

  test 'dashboard import creates approved visible concerts' do
    run = create_run!(import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_DASHBOARD)

    SongkickConcerts::Importer.new(run: run, client: client_for(events_html([event_payload]))).perform!

    venue = Venue.find_by!(category: 'concierto', external_source_id: '123')
    assert_equal Venue::REVIEW_STATUS_APPROVED, venue.review_status
    assert venue.visible
    assert_equal Venue::EVENT_STATUS_UPCOMING, venue.event_status
    assert_equal Venue::EVENT_IMPORT_ORIGIN_DASHBOARD, venue.event_import_origin
    assert_equal 1, run.reload.venues_created_count
  end

  test 'cron import creates pending hidden concerts' do
    run = create_run!(import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_CRON)

    SongkickConcerts::Importer.new(run: run, client: client_for(events_html([event_payload(id: 456, name: 'Cron Artist at Sala Test')]))).perform!

    venue = Venue.find_by!(category: 'concierto', external_source_id: '456')
    assert_equal Venue::REVIEW_STATUS_PENDING, venue.review_status
    refute venue.visible
    assert_equal Venue::EVENT_IMPORT_ORIGIN_CRON, venue.event_import_origin
  end

  test 'repeated imports skip an already created concert' do
    first_run = create_run!(import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_DASHBOARD)
    second_run = create_run!(import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_DASHBOARD)
    html = events_html([event_payload])

    SongkickConcerts::Importer.new(run: first_run, client: client_for(html)).perform!
    SongkickConcerts::Importer.new(run: second_run, client: client_for(html)).perform!

    assert_equal 1, Venue.where(category: 'concierto', external_source_id: '123').count
    assert_equal 1, second_run.reload.duplicate_skipped_count
  end

  test 'same artist same venue on a different date is not merged' do
    run = create_run!(import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_DASHBOARD)
    first = event_payload(id: 111, name: 'Repeat Artist at Sala Test', start_date: '2026-11-20T21:00:00')
    second = event_payload(id: 222, name: 'Repeat Artist at Sala Test', start_date: '2026-11-21T21:00:00')

    SongkickConcerts::Importer.new(run: run, client: client_for(events_html([first, second]))).perform!

    assert_equal 2, Venue.where(category: 'concierto', city: 'Madrid').count
  end

  test 'festival-like events are discarded without becoming visible import items' do
    run = create_run!(import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_DASHBOARD)
    festival = event_payload(
      id: 999,
      name: 'Festival de Prueba 2026',
      start_date: '2026-11-20T18:00:00'
    ).merge(
      '@type' => 'MusicFestival',
      '@id' => 'https://www.songkick.com/festivals/999-festival-de-prueba#event',
      'url' => 'https://www.songkick.com/festivals/999-festival-de-prueba'
    )

    SongkickConcerts::Importer.new(run: run, client: client_for(events_html([festival]))).perform!

    assert_equal 0, run.items.count
    assert_equal 0, run.reload.candidates_found_count
    assert_equal 1, run.non_concert_skipped_count
    assert_equal 0, Venue.where(category: 'concierto', external_source_id: '999').count
  end

  private

  def required_columns_present?
    run_columns = %w[import_origin non_concert_skipped_count]
    item_columns = %w[start_at end_at event_dedupe_key]
    venue_columns = %w[review_status visible external_source external_source_id event_status event_import_origin event_dedupe_key event_start_at event_end_at festival_start_date]

    run_columns.all? { |column| BlackCoffeeConcertImportRun.column_names.include?(column) } &&
      item_columns.all? { |column| BlackCoffeeConcertImportItem.column_names.include?(column) } &&
      venue_columns.all? { |column| Venue.column_names.include?(column) }
  end

  def create_run!(import_origin:)
    BlackCoffeeConcertImportRun.create!(
      source: BlackCoffeeConcertImportRun::SOURCE_SONGKICK,
      mode: 'import',
      status: 'pending',
      source_url: SongkickConcerts::Client::BASE_URL,
      source_paths: '/metro-areas/28755-spain-madrid',
      max_pages_per_source: 1,
      max_events: 10,
      request_delay_seconds: 10,
      strict_country_code: 'ES',
      download_images: false,
      only_future: true,
      auto_publish: false,
      preserve_manual_edits: true,
      import_origin: import_origin
    )
  end

  def client_for(html)
    FakeClient.new(html, 0, 0, 0)
  end

  def events_html(events)
    <<~HTML
      <html>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@graph": #{events.to_json}
          }
        </script>
      </html>
    HTML
  end

  def event_payload(id: 123, name: 'Artist Uno at Sala Test', start_date: '2026-11-20T21:00:00')
    {
      '@type' => 'MusicEvent',
      '@id' => "https://www.songkick.com/concerts/#{id}-test-concert#event",
      'url' => "https://www.songkick.com/concerts/#{id}-test-concert",
      'name' => name,
      'startDate' => start_date,
      'description' => 'A properly long Songkick concert description that should stay pending editorial review.',
      'performer' => [{ 'name' => name.split(' at ').first, 'genre' => ['rock'] }],
      'location' => {
        'name' => 'Sala Test',
        'address' => {
          'streetAddress' => 'Calle Test 1',
          'addressLocality' => 'Madrid',
          'addressRegion' => 'Comunidad de Madrid',
          'addressCountry' => 'Spain'
        },
        'geo' => {
          'latitude' => '40.416775',
          'longitude' => '-3.703790'
        }
      }
    }
  end
end
