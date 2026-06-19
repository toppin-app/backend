module FanMusicFest
  class DetailRefresher
    Result = Struct.new(:venue, :normalized, :changes, :warnings, keyword_init: true)

    def initialize(client: Client.new, parser: Parser.new, normalizer: Normalizer.new)
      @client = client
      @parser = parser
      @normalizer = normalizer
    end

    def call(venue:, dry_run: true, preserve_manual_edits: true)
      source_url = venue.safe_fan_music_fest_source_url
      raise ArgumentError, 'El festival no tiene una URL valida de FanMusicFest.' if source_url.blank?

      html = @client.fetch_detail(source_url)
      raw = @parser.parse_detail(html, source_url: source_url)
      normalized = @normalizer.normalize(raw)
      raise ArgumentError, 'FanMusicFest devolvio un festival fuera de Espana.' if normalized[:outside_country]
      raise ArgumentError, 'La ficha no contiene los datos minimos del festival.' unless normalized[:valid]

      attributes, warnings = refresh_attributes(
        venue,
        normalized,
        preserve_manual_edits: preserve_manual_edits
      )
      changes = changed_attributes(venue, attributes)
      venue.update!(attributes) unless dry_run || changes.empty?

      Result.new(
        venue: venue,
        normalized: normalized,
        changes: changes,
        warnings: warnings
      )
    end

    private

    def refresh_attributes(venue, normalized, preserve_manual_edits:)
      attributes = source_attributes(
        venue,
        normalized,
        preserve_manual_edits: preserve_manual_edits
      )
      warnings = Array(normalized[:coordinates_warning]).compact

      apply_coordinates!(
        attributes,
        warnings,
        venue,
        normalized,
        preserve_manual_edits: preserve_manual_edits
      )
      apply_optional_url!(
        attributes,
        venue,
        :official_url,
        normalized[:official_url],
        preserve_manual_edits: preserve_manual_edits
      )
      apply_optional_url!(
        attributes,
        venue,
        :ticket_url,
        normalized[:ticket_url],
        preserve_manual_edits: preserve_manual_edits
      )

      [attributes.compact, warnings]
    end

    def source_attributes(venue, normalized, preserve_manual_edits:)
      attributes = {
        external_source_url: normalized[:source_url],
        external_source_id: normalized[:source_event_id],
        source_fingerprint: normalized[:fingerprint],
        source_description: normalized[:source_description],
        source_description_language: normalized[:source_description_language],
        source_description_status: next_description_status(venue, normalized),
        festival_metadata: merged_metadata(venue, normalized)
      }

      apply_source_detail!(
        attributes,
        venue,
        :festival_start_date,
        normalized[:start_date],
        preserve_manual_edits: preserve_manual_edits
      )
      apply_source_detail!(
        attributes,
        venue,
        :festival_end_date,
        normalized[:end_date],
        preserve_manual_edits: preserve_manual_edits
      )
      apply_source_detail!(
        attributes,
        venue,
        :festival_venue_name,
        normalized[:venue_name],
        preserve_manual_edits: preserve_manual_edits
      )
      apply_source_detail!(
        attributes,
        venue,
        :festival_raw_location_text,
        normalized[:raw_location_text],
        preserve_manual_edits: preserve_manual_edits
      )

      attributes.select { |key, _value| venue.has_attribute?(key) }
    end

    def next_description_status(venue, normalized)
      return 'not_found' if normalized[:source_description].blank?
      return 'needs_review' unless venue.has_attribute?(:source_description_status)

      current_status = venue.source_description_status.to_s
      current_description = venue.source_description.to_s.squish
      incoming_description = normalized[:source_description].to_s.squish
      return current_status if %w[approved rejected].include?(current_status) && current_description == incoming_description

      'needs_review'
    end

    def merged_metadata(venue, normalized)
      existing = venue.has_attribute?(:festival_metadata) && venue.festival_metadata.is_a?(Hash) ? venue.festival_metadata : {}
      existing.merge(
        'edition_title' => normalized[:edition_title],
        'event_status' => normalized[:event_status],
        'free' => normalized[:free],
        'organizer' => normalized[:organizer],
        'offers' => normalized[:offers],
        'performers' => normalized[:performers],
        'ticket_price_text' => normalized[:ticket_price_text],
        'map_source_url' => normalized[:map_source_url],
        'source' => Normalizer::SOURCE
      ).compact
    end

    def apply_coordinates!(attributes, warnings, venue, normalized, preserve_manual_edits:)
      return if normalized[:latitude].blank? || normalized[:longitude].blank?

      can_replace = !preserve_manual_edits ||
                    venue.latitude.blank? ||
                    venue.longitude.blank? ||
                    source_managed_coordinates?(venue)

      unless can_replace
        warnings << 'Se conservaron las coordenadas existentes porque pueden haber sido editadas manualmente.'
        return
      end

      attributes[:latitude] = normalized[:latitude]
      attributes[:longitude] = normalized[:longitude]
      attributes[:coordinates_source] = normalized[:coordinates_source] if venue.has_attribute?(:coordinates_source)
      attributes[:coordinates_confidence] = normalized[:coordinates_confidence] if venue.has_attribute?(:coordinates_confidence)
    end

    def source_managed_coordinates?(venue)
      return false unless venue.has_attribute?(:coordinates_source)

      venue.coordinates_source.blank? || venue.coordinates_source.to_s.start_with?('fanmusicfest', 'schema_org', 'open_graph', 'map_link')
    end

    def apply_optional_url!(attributes, venue, attribute, value, preserve_manual_edits:)
      return unless venue.has_attribute?(attribute)
      return if value.blank?
      return if preserve_manual_edits && venue.public_send(attribute).present?

      attributes[attribute] = value
    end

    def apply_source_detail!(attributes, venue, attribute, value, preserve_manual_edits:)
      return unless venue.has_attribute?(attribute)
      return if value.blank?
      return if preserve_manual_edits && venue.public_send(attribute).present?

      attributes[attribute] = value
    end

    def changed_attributes(venue, attributes)
      attributes.each_with_object({}) do |(key, value), changes|
        current = venue.public_send(key)
        changes[key] = { from: current, to: value } unless comparable(current) == comparable(value)
      end
    end

    def comparable(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : value
    end
  end
end
