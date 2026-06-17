require 'test_helper'

class FanMusicFestParserTest < ActiveSupport::TestCase
  SAMPLE_HTML = <<~HTML
    <html>
      <head>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@graph": [
              { "@type": "WebPage", "name": "Calendario" },
              {
                "@type": "Festival",
                "@id": "https://fanmusicfest.com/content/coruna-sounds-2026#event",
                "name": "Coruna Sounds 2026 | Cartel y entradas",
                "url": "/content/coruna-sounds-2026",
                "location": {
                  "@type": "Place",
                  "address": {
                    "@type": "PostalAddress",
                    "addressCountry": "Espana"
                  }
                }
              }
            ]
          }
        </script>
      </head>
    </html>
  HTML

  test 'extracts festival JSON-LD nodes from listing pages' do
    events = FanMusicFest::Parser.new.parse_listing(SAMPLE_HTML)

    assert_equal 1, events.size
    assert_equal 'Coruna Sounds 2026 | Cartel y entradas', events.first['name']
    assert_equal 'https://fanmusicfest.com/content/coruna-sounds-2026', events.first['url']
  end
end
