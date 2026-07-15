require 'test_helper'

class SongkickConcertsParserTest < ActiveSupport::TestCase
  SAMPLE_HTML = <<~HTML
    <html>
      <head>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@graph": [
              { "@type": "WebPage", "name": "Madrid concerts" },
              {
                "@type": "MusicEvent",
                "@id": "https://www.songkick.com/concerts/123-test-concert#event",
                "name": "Artist Uno at Sala Test",
                "url": "/concerts/123-test-concert",
                "startDate": "2026-11-20T21:00:00",
                "location": {
                  "@type": "Place",
                  "name": "Sala Test"
                }
              }
            ]
          }
        </script>
        <script type="application/ld+json">
          {
            "@type": "MusicEvent",
            "@id": "https://www.songkick.com/concerts/123-test-concert#event",
            "name": "Artist Uno at Sala Test",
            "url": "/concerts/123-test-concert"
          }
        </script>
      </head>
      <body>
        <nav class="pagination">
          <a class="next_page" href="/metro-areas/28755-spain-madrid?page=2">Next</a>
        </nav>
      </body>
    </html>
  HTML

  test 'extracts unique MusicEvent JSON-LD nodes from listing pages' do
    events = SongkickConcerts::Parser.new.parse_listing(SAMPLE_HTML)

    assert_equal 1, events.size
    assert_equal 'Artist Uno at Sala Test', events.first['name']
    assert_equal 'https://www.songkick.com/concerts/123-test-concert', events.first['url']
  end

  test 'detects next page links from Songkick pagination' do
    parser = SongkickConcerts::Parser.new

    assert parser.next_page?(SAMPLE_HTML)
    assert_not parser.next_page?('<html><body>No pagination</body></html>')
  end

  test 'passes festival nodes to the importer so they can be counted and discarded' do
    html = <<~HTML
      <script type="application/ld+json">
        {
          "@type": "MusicFestival",
          "name": "Festival que no debe importarse",
          "url": "/festivals/999-festival"
        }
      </script>
    HTML

    events = SongkickConcerts::Parser.new.parse_listing(html)

    assert_equal 1, events.size
    assert_equal 'MusicFestival', events.first['@type']
  end

  test 'ignores malformed JSON-LD without raising' do
    html = '<script type="application/ld+json">{not-json</script>'

    assert_equal [], SongkickConcerts::Parser.new.parse_listing(html)
  end
end
