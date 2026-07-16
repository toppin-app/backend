require 'nokogiri'

module BlackCoffeeConcertCoverSearch
  module Providers
    class WikimediaCommons < Base
      KEY = 'wikimedia_commons'.freeze
      API_URL = 'https://commons.wikimedia.org/w/api.php'.freeze
      ALLOWED_MIME_TYPES = %w[image/jpeg image/png image/webp].freeze
      REJECTED_LICENSE_TOKENS = ['noncommercial', 'non-commercial', '-nc', 'no derivatives', '-nd', 'fair use', 'all rights reserved'].freeze

      attr_reader :requests_count

      def initialize(client: HttpClient.new(allowed_hosts: ['commons.wikimedia.org']), thumbnail_width: 1200)
        @client = client
        @thumbnail_width = [[thumbnail_width.to_i, 400].max, 2_000].min
        @requests_count = 0
      end

      def search(context)
        before = requests_count
        identities = identities_from(context).select { |identity| identity[:image_file].present? }
        return not_found(before, 'Ninguna identidad validable ofrece P18 en Wikidata.') if identities.empty?

        titles = identities.map { |identity| file_title(identity[:image_file]) }.uniq
        response = request_json(
          action: 'query',
          prop: 'imageinfo',
          titles: titles.join('|'),
          iiprop: 'url|size|mime|sha1|extmetadata',
          iiurlwidth: @thumbnail_width,
          iimetadataversion: 'latest',
          iiextmetadatalanguage: 'en',
          iiextmetadatafilter: 'LicenseShortName|LicenseUrl|Artist|Credit|Attribution|AttributionRequired|UsageTerms|ImageDescription',
          format: 'json',
          maxlag: 5
        )
        return provider_failure(response, requests_count: requests_count - before) unless response.ok?

        candidates = []
        rejections = []
        response.json.dig('query', 'pages').to_h.each_value do |page|
          info = Array(page['imageinfo']).first
          unless info
            rejections << { file: page['title'], reason: 'missing_imageinfo' }
            next
          end

          matching_identities = identities.select { |identity| normalized_file(identity[:image_file]) == normalized_file(page['title']) }
          if matching_identities.empty?
            rejections << { file: page['title'], reason: 'identity_mapping_failed' }
            next
          end

          validation = validate_file(info)
          unless validation[:ok]
            rejections << { file: page['title'], reason: validation[:reason] }
            next
          end

          matching_identities.each do |identity|
            candidates << candidate_from(page, info, identity, validation[:license])
          end
        end

        return not_found(before, 'Commons no devolvio una imagen con licencia y formato admitidos.', rejections) if candidates.empty?

        ProviderResult.ok(
          candidates: candidates,
          identifiers: candidates.first.identifiers || {},
          evidence: { files_queried: titles.size, rejected_files: rejections },
          requests_count: requests_count - before
        )
      rescue StandardError => e
        ProviderResult.failure(
          status: 'unavailable',
          error_type: 'commons_parse_error',
          error_message: "#{e.class}: #{e.message}",
          requests_count: requests_count - before.to_i
        )
      end

      private

      def request_json(params)
        @requests_count += 1
        @client.get(API_URL, params: params)
      end

      def file_title(value)
        title = value.to_s.tr('_', ' ').strip
        title.match?(/\AFile:/i) ? title : "File:#{title}"
      end

      def normalized_file(value)
        value.to_s.sub(/\AFile:/i, '').tr('_', ' ').squish.downcase
      end

      def validate_file(info)
        mime = info['mime'].to_s.downcase
        return { ok: false, reason: 'unsupported_mime' } unless ALLOWED_MIME_TYPES.include?(mime)
        return { ok: false, reason: 'missing_dimensions' } unless info['width'].to_i.positive? && info['height'].to_i.positive?

        license = license_metadata(info['extmetadata'])
        return { ok: false, reason: 'unsupported_license' } unless allowed_license?(license)

        { ok: true, license: license }
      end

      def license_metadata(extmetadata)
        metadata = extmetadata.to_h
        {
          name: metadata_value(metadata, 'LicenseShortName'),
          url: metadata_value(metadata, 'LicenseUrl'),
          artist: metadata_value(metadata, 'Artist'),
          credit: metadata_value(metadata, 'Credit'),
          attribution: metadata_value(metadata, 'Attribution'),
          attribution_required: metadata_value(metadata, 'AttributionRequired'),
          usage_terms: metadata_value(metadata, 'UsageTerms'),
          description: metadata_value(metadata, 'ImageDescription')
        }.compact
      end

      def metadata_value(metadata, key)
        raw = metadata.dig(key, 'value').to_s
        Nokogiri::HTML.fragment(raw).text.squish.presence
      end

      def allowed_license?(license)
        name = license[:name].to_s.downcase
        terms = license[:usage_terms].to_s.downcase
        combined = "#{name} #{terms}"
        return false if name.blank?
        return false if REJECTED_LICENSE_TOKENS.any? { |token| combined.include?(token) }

        public_domain = combined.include?('public domain') || name.include?('cc0') || name.include?('pdm')
        creative_commons = name.match?(/\Acc[ -]?by(?:-sa)?(?:[\s-]|\z)/i) || name.include?('creative commons attribution')
        return true if public_domain
        return false unless creative_commons

        license[:url].present? && (license[:artist].present? || license[:credit].present? || license[:attribution].present?)
      end

      def candidate_from(page, info, identity, license)
        use_thumbnail = info['thumburl'].present?
        Candidate.new(
          image_url: use_thumbnail ? info['thumburl'] : info['url'],
          page_url: info['descriptionurl'].presence || info['descriptionshorturl'],
          provider: KEY,
          width: use_thumbnail ? info['thumbwidth'].to_i : info['width'].to_i,
          height: use_thumbnail ? info['thumbheight'].to_i : info['height'].to_i,
          identifiers: identity.fetch(:identifiers, {}).dup,
          evidence: {
            identity: identity,
            file_title: page['title'],
            original_url: info['url'],
            mime_type: info['mime'],
            sha1: info['sha1'],
            original_width: info['width'].to_i,
            original_height: info['height'].to_i,
            license: license,
            attribution: {
              text: license[:attribution].presence || license[:credit].presence || license[:artist],
              artist: license[:artist],
              license: license[:name],
              license_url: license[:url],
              source_url: info['descriptionurl']
            }.compact
          }
        )
      end

      def not_found(before, message, rejections = [])
        ProviderResult.failure(
          status: 'not_found',
          error_type: 'commons_not_found',
          error_message: message,
          evidence: { rejected_files: rejections },
          requests_count: requests_count - before
        )
      end
    end
  end
end
