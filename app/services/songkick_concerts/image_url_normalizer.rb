require 'cgi'
require 'uri'

module SongkickConcerts
  class ImageUrlNormalizer
    IMAGE_URL_KEYS = %w[url contentUrl content_url thumbnailUrl thumbnail_url].freeze
    PLACEHOLDER_PATH_PATTERNS = [
      %r{/(?:default_images|placeholders?|icons?|logos?|branding|sprites?)/}i,
      %r{(?:\A|[/_.-])(?:default[-_]?artist|default[-_]?image|placeholder|no[-_]?image|image[-_]?missing|missing[-_]?image|fallback|spacer|transparent|blank|spinner|loading|favicon|sprite|pixel|logo|icon)(?:[/_.-]|\z)}i,
      %r{/page-view\.png\z}i
    ].freeze
    PLACEHOLDER_HINT_PATTERN = /\b(?:default image|default artist|placeholder|no image|missing image|fallback|spacer|transparent|spinner|loading|favicon|sprite|pixel|logo|icon|navigation)\b/i

    class << self
      def normalize(value, base_url:)
        raw_url = CGI.unescapeHTML(value.to_s).strip
        return nil if raw_url.empty?

        uri = URI.parse(raw_url)
        uri = URI.join(base_url.to_s, raw_url) unless uri.scheme
        return nil unless uri.is_a?(URI::HTTP) && uri.host.to_s.strip != ''

        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      def extract(value, base_url:)
        raw_urls(value).filter_map { |entry| normalize(entry, base_url: base_url) }
                       .reject { |url| placeholder?(url) }
                       .uniq
                       .each_with_index
                       .sort_by { |(url, index)| [-quality_score(url), index] }
                       .map(&:first)
      end

      def srcset_entries(value, base_url:)
        value.to_s.split(',').filter_map do |entry|
          url_value, descriptor = entry.strip.split(/\s+/, 2)
          url = normalize(url_value, base_url: base_url)
          next if url.nil? || placeholder?(url)

          {
            url: url,
            descriptor: descriptor.to_s.strip.presence,
            score: descriptor_score(descriptor) + quality_score(url)
          }
        end
      end

      def placeholder?(url, hint: nil)
        uri = URI.parse(url.to_s)
        path = CGI.unescape(uri.path.to_s).downcase
        return true if PLACEHOLDER_PATH_PATTERNS.any? { |pattern| path.match?(pattern) }

        hint.to_s.match?(PLACEHOLDER_HINT_PATTERN)
      rescue URI::InvalidURIError
        true
      end

      def quality_score(url)
        path = URI.parse(url.to_s).path.to_s.downcase
        return 48 if path.match?(/(?:huge|original|full)(?:[_-]avatar)?(?:\.|\/|\z)/)
        return 44 if path.match?(/col6(?:\.|\/|\z)/)
        return 36 if path.match?(/(?:large|col5)(?:[_-]avatar)?(?:\.|\/|\z)/)
        return 22 if path.match?(/col4(?:\.|\/|\z)/)
        return 10 if path.match?(/col3(?:\.|\/|\z)/)
        return -20 if path.match?(/medium(?:[_-]avatar)?(?:\.|\/|\z)/)
        return -30 if path.match?(/(?:thumb|small|tiny)(?:[_-]avatar)?(?:\.|\/|\z)/)

        0
      rescue URI::InvalidURIError
        0
      end

      private

      def raw_urls(value)
        case value
        when Array
          value.flat_map { |entry| raw_urls(entry) }
        when Hash
          normalized = value.stringify_keys
          direct_urls = IMAGE_URL_KEYS.flat_map { |key| raw_urls(normalized[key]) }
          direct_urls + raw_urls(normalized['image'])
        else
          value.to_s.strip.empty? ? [] : [value]
        end
      end

      def descriptor_score(descriptor)
        value = descriptor.to_s.strip
        return [[value.to_i / 100, 0].max, 24].min if value.match?(/\A\d+w\z/)
        return [[(value.to_f * 8).round, 0].max, 24].min if value.match?(/\A\d+(?:\.\d+)?x\z/)

        0
      end
    end
  end
end
