require 'set'

module BlackCoffeeConcertCoverSearch
  class Matcher
    Match = Struct.new(:result, :confidence, :evidence, keyword_init: true)

    STOP_WORDS = %w[
      a al and at con concierto concert de del el en la las live los the tour y
    ].freeze
    MONTH_NAMES = %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].freeze
    MIN_NAME_COVERAGE = 0.75
    MIN_IMAGE_SIDE = 240

    def best_match(results:, event:)
      Array(results).filter_map { |result| match(result, event) }
                    .max_by(&:confidence)
    end

    def match(result, event)
      text = canonical_text([result.title, result.description, result.page_url, result.publisher].compact.join(' '))
      text_tokens = text.split.to_set
      name_tokens = significant_tokens(event[:name])
      return nil if name_tokens.empty?

      matched_name_tokens = name_tokens.count { |token| text_tokens.include?(token) }
      name_coverage = matched_name_tokens.to_f / name_tokens.size
      return nil if name_coverage < MIN_NAME_COVERAGE

      date_variants = date_variants_for(event[:date])
      date_match = date_variants.any? { |variant| text.include?(canonical_text(variant)) }
      return nil unless date_match

      location_tokens = significant_tokens([event[:venue_name], event[:city]].compact.join(' '))
      location_match = location_tokens.empty? || location_tokens.any? { |token| text_tokens.include?(token) }
      return nil unless location_match
      return nil if image_too_small?(result)

      confidence = ((name_coverage * 65) + 25 + (location_tokens.empty? ? 5 : 10)).round(2)
      Match.new(
        result: result,
        confidence: confidence,
        evidence: {
          name_coverage: name_coverage.round(2),
          matched_name_tokens: matched_name_tokens,
          total_name_tokens: name_tokens.size,
          date_match: true,
          location_match: location_match,
          image_width: result.width,
          image_height: result.height
        }
      )
    end

    private

    def canonical_text(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish
    end

    def significant_tokens(value)
      canonical_text(value).split.reject do |token|
        token.length < 3 || STOP_WORDS.include?(token)
      end.uniq
    end

    def date_variants_for(value)
      date = value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
      month = MONTH_NAMES.fetch(date.month - 1)
      [
        date.iso8601,
        date.strftime('%d/%m/%Y'),
        date.strftime('%d-%m-%Y'),
        "#{date.day} #{month} #{date.year}",
        "#{date.day} de #{month} de #{date.year}"
      ]
    rescue ArgumentError, TypeError
      []
    end

    def image_too_small?(result)
      return false if result.width.blank? || result.height.blank?

      result.width.to_i < MIN_IMAGE_SIDE || result.height.to_i < MIN_IMAGE_SIDE
    end
  end
end
