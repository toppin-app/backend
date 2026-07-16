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

  test 'normalizes a direct JSON-LD image from a listing page' do
    html = <<~HTML
      <script type="application/ld+json">
        {
          "@type": "MusicEvent",
          "name": "Artist Uno at Sala Test",
          "url": "/concerts/123-test-concert",
          "image": "//images.sk-static.com/images/media/profile_images/artists/123/huge_avatar"
        }
      </script>
    HTML

    event = SongkickConcerts::Parser.new.parse_listing(html).first

    expected = 'https://images.sk-static.com/images/media/profile_images/artists/123/huge_avatar'
    assert_equal expected, event['image']
    assert_equal [expected], event['image_candidates']
  end

  test 'detects next page links from Songkick pagination' do
    parser = SongkickConcerts::Parser.new

    assert parser.next_page?(SAMPLE_HTML)
    assert_not parser.next_page?('<html><body>No pagination</body></html>')
  end

  test 'extracts unique Open Graph and Twitter image candidates from an event page' do
    html = <<~HTML
      <html><head>
        <meta property="og:image" content="https://images.example.test/event-cover.jpg">
        <meta property="og:image:secure_url" content="https://images.example.test/event-cover.jpg">
        <meta name="twitter:image" content="https://images.example.test/artist-cover.jpg">
      </head></html>
    HTML

    urls = SongkickConcerts::Parser.new.page_image_urls(html)

    assert_equal [
      'https://images.example.test/event-cover.jpg',
      'https://images.example.test/artist-cover.jpg'
    ], urls
  end

  test 'extracts JSON-LD event and performer images from a detail page' do
    html = <<~HTML
      <script type="application/ld+json">
        {
          "@type": "MusicEvent",
          "name": "Artist Uno at Sala Test",
          "image": "/images/event-full.jpg",
          "performer": {
            "@type": "MusicGroup",
            "name": "Artist Uno",
            "image": {"contentUrl": "//cdn.example.test/artists/artist-large.jpg"}
          }
        }
      </script>
    HTML

    urls = SongkickConcerts::Parser.new.page_image_urls(
      html,
      base_url: 'https://www.songkick.com/concerts/123-test-concert'
    )

    assert_equal 'https://www.songkick.com/images/event-full.jpg', urls.first
    assert_includes urls, 'https://cdn.example.test/artists/artist-large.jpg'
  end

  test 'extracts lazy image attributes and normalizes their URLs' do
    html = <<~HTML
      <div class="lineup">
        <img alt="Artist Uno" data-src="/images/artist.jpg">
        <img alt="Artist Dos" data-lazy-src="//cdn.example.test/artist-two.jpg">
        <img alt="Artist Tres" data-original="images/artist-original.jpg">
      </div>
    HTML

    urls = SongkickConcerts::Parser.new.page_image_urls(
      html,
      base_url: 'https://www.songkick.com/concerts/123-test-concert'
    )

    assert_includes urls, 'https://www.songkick.com/images/artist.jpg'
    assert_includes urls, 'https://cdn.example.test/artist-two.jpg'
    assert_includes urls, 'https://www.songkick.com/concerts/images/artist-original.jpg'
  end

  test 'ranks the largest responsive srcset candidate first' do
    html = <<~HTML
      <picture class="event-hero">
        <source srcset="/images/artist-small.jpg 320w, //cdn.example.test/artist/huge_avatar 1200w">
        <img src="/images/artist-medium.jpg" alt="Artist Uno">
      </picture>
    HTML

    urls = SongkickConcerts::Parser.new.page_image_urls(
      html,
      base_url: 'https://www.songkick.com/concerts/123-test-concert'
    )

    assert_equal 'https://cdn.example.test/artist/huge_avatar', urls.first
    assert_includes urls, 'https://www.songkick.com/images/artist-small.jpg'
    assert_includes urls, 'https://www.songkick.com/images/artist-medium.jpg'
  end

  test 'extracts image_src and regular img sources with relative URLs' do
    html = <<~HTML
      <head><link rel="image_src" href="/images/profile.jpg"></head>
      <body><img src="images/lineup.jpg" alt="Artist Uno"></body>
    HTML

    urls = SongkickConcerts::Parser.new.page_image_urls(
      html,
      base_url: 'https://www.songkick.com/concerts/123-test-concert'
    )

    assert_includes urls, 'https://www.songkick.com/images/profile.jpg'
    assert_includes urls, 'https://www.songkick.com/concerts/images/lineup.jpg'
  end

  test 'discards a first placeholder candidate and keeps the working artist image' do
    html = <<~HTML
      <head>
        <meta property="og:image" content="//assets.sk-static.com/images/default_images/large_avatar/default-artist.png">
      </head>
      <body>
        <img src="/images/icons/photo.svg" alt="Photo icon">
        <img data-src="/images/artists/artist-uno.jpg" alt="Artist Uno">
      </body>
    HTML

    urls = SongkickConcerts::Parser.new.page_image_urls(html)

    assert_equal ['https://www.songkick.com/images/artists/artist-uno.jpg'], urls
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
