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

  test 'extracts detail coordinates description and useful links' do
    html = <<~HTML
      <html>
        <head>
          <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Festival",
              "@id": "https://fanmusicfest.com/content/test-fest-2026#event",
              "name": "Test Fest 2026",
              "url": "https://fanmusicfest.com/content/test-fest-2026",
              "description": "Una descripcion limpia y suficientemente extensa sobre el festival y su propuesta musical.",
              "location": {
                "name": "Recinto Test",
                "address": {
                  "addressLocality": "Valencia",
                  "addressCountry": "España"
                },
                "geo": { "latitude": "39.462085", "longitude": "-0.320926" }
              }
            }
          </script>
        </head>
        <body>
          <a data-content="&lt;a href='https://testfest.example/'&gt;Website&lt;/a&gt;"></a>
          <div id="block-views-fmf-festivales-block-entradas">
            <a href="https://tickets.example/test-fest">Entrada General</a>
            <div class="card__precio">44,90€</div>
          </div>
        </body>
      </html>
    HTML

    detail = FanMusicFest::Parser.new.parse_detail(
      html,
      source_url: 'https://fanmusicfest.com/content/test-fest-2026'
    )
    metadata = detail['_fanmusicfest_detail']

    assert_equal 39.462085, metadata.dig('coordinates', 'latitude')
    assert_equal(-0.320926, metadata.dig('coordinates', 'longitude'))
    assert_equal 'schema_org', metadata.dig('coordinates', 'source')
    assert_equal 'high', metadata.dig('coordinates', 'confidence')
    assert_equal 'https://testfest.example/', metadata['official_url']
    assert_equal 'https://tickets.example/test-fest', metadata['ticket_url']
    assert_equal '44,90€', metadata['ticket_price_text']
    assert_match(/descripcion limpia/, metadata['source_description'])
  end

  test 'rejects coordinates outside Spain and supports pages without descriptions' do
    html = <<~HTML
      <html>
        <script type="application/ld+json">
          {
            "@type": "Festival",
            "name": "Outside Fest",
            "url": "https://fanmusicfest.com/content/outside-fest",
            "location": {
              "address": {
                "addressLocality": "Paris",
                "addressCountry": "France"
              },
              "geo": { "latitude": "48.8566", "longitude": "2.3522" }
            }
          }
        </script>
      </html>
    HTML

    detail = FanMusicFest::Parser.new.parse_detail(
      html,
      source_url: 'https://fanmusicfest.com/content/outside-fest'
    )
    metadata = detail['_fanmusicfest_detail']

    assert_equal 'none', metadata.dig('coordinates', 'confidence')
    assert_match(/fuera de los limites/, metadata.dig('coordinates', 'warning'))
    assert_nil metadata['source_description']
  end

  test 'extracts coordinates from map iframe and inline script fallbacks' do
    parser = FanMusicFest::Parser.new
    iframe_coordinates = parser.extract_map_coordinates_from_festival_detail(<<~HTML)
      <iframe src="https://www.google.com/maps/embed/v1/place?q=39.4699,-0.3763"></iframe>
    HTML
    script_coordinates = parser.extract_map_coordinates_from_festival_detail(<<~HTML)
      <script>
        window.festivalMap = { latitude: 41.3851, longitude: 2.1734 };
      </script>
    HTML
    data_coordinates = parser.extract_map_coordinates_from_festival_detail(<<~HTML)
      <div data-lat="37.3891" data-lng="-5.9845"></div>
    HTML

    assert_equal 39.4699, iframe_coordinates['latitude']
    assert_equal(-0.3763, iframe_coordinates['longitude'])
    assert_equal 'map_link', iframe_coordinates['source']
    assert_equal 'medium', iframe_coordinates['confidence']
    assert_equal 41.3851, script_coordinates['latitude']
    assert_equal 2.1734, script_coordinates['longitude']
    assert_equal 'inline_script', script_coordinates['source']
    assert_equal 'low', script_coordinates['confidence']
    assert_equal 37.3891, data_coordinates['latitude']
    assert_equal(-5.9845, data_coordinates['longitude'])
    assert_equal 'fanmusicfest_map', data_coordinates['source']
  end
end
