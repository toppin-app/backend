module Api
  module BlackCoffee
    module Admin
      class ConcertImportsController < BaseController
        skip_before_action :authenticate_user!, if: :cron_token_request?
        before_action :authorize_request!

        def create
          mark_occurred_result = BlackCoffeeConcertLifecycle.mark_past_concerts_occurred!
          run = SongkickConcerts::Importer.enqueue!(
            attributes: cron_import_attributes(mark_occurred_result)
          )

          render json: {
            success: true,
            queued: true,
            run_id: run.id,
            import_origin: run.import_origin,
            publication: {
              visible: false,
              review_status: Venue::REVIEW_STATUS_PENDING
            },
            past_concerts_marked_occurred: mark_occurred_result.marked_occurred_count,
            message: 'Songkick concert import queued for cron'
          }, status: :ok
        rescue StandardError => e
          render json: {
            success: false,
            error: e.message,
            message: 'Songkick concert cron import failed to enqueue'
          }, status: :unprocessable_entity
        end

        def mark_occurred
          result = BlackCoffeeConcertLifecycle.mark_past_concerts_occurred!

          render json: {
            success: true,
            marked_occurred: result.marked_occurred_count,
            reference_date: result.reference_date.iso8601,
            message: 'Past Black Coffee concerts marked as occurred'
          }, status: :ok
        rescue StandardError => e
          render json: {
            success: false,
            error: e.message,
            message: 'Could not mark past Black Coffee concerts as occurred'
          }, status: :unprocessable_entity
        end

        private

        def authorize_request!
          return if cron_token_request?

          require_admin!
        end

        def cron_token_request?
          valid_cron_token?(params[:token])
        end

        def valid_cron_token?(provided_token)
          provided = provided_token.to_s
          expected = UsersController::CRON_TOKEN.to_s
          return false if provided.blank? || expected.blank?
          return false unless provided.bytesize == expected.bytesize

          ActiveSupport::SecurityUtils.secure_compare(provided, expected)
        end

        def cron_import_attributes(mark_occurred_result)
          {
            mode: 'import',
            status: 'pending',
            source_paths: SongkickConcerts::Importer::DEFAULT_SOURCE_PATHS_TEXT,
            max_pages_per_source: clamped_integer(params[:max_pages_per_source], default: 10, min: 1, max: SongkickConcerts::Importer::MAX_PAGES_PER_SOURCE),
            max_events: clamped_integer(params[:max_events], default: SongkickConcerts::Importer::MAX_EVENTS, min: 1, max: SongkickConcerts::Importer::MAX_EVENTS),
            request_delay_seconds: clamped_decimal(params[:request_delay_seconds], default: SongkickConcerts::Client::DEFAULT_CRAWL_DELAY_SECONDS, min: SongkickConcerts::Client::DEFAULT_CRAWL_DELAY_SECONDS, max: 120),
            strict_country_code: 'ES',
            download_images: true,
            only_future: true,
            auto_publish: false,
            preserve_manual_edits: true,
            import_origin: BlackCoffeeConcertImportRun::IMPORT_ORIGIN_CRON,
            occurred_marked_count: mark_occurred_result.marked_occurred_count
          }
        end

        def clamped_integer(value, default:, min:, max:)
          parsed = value.to_s.strip.presence&.to_i || default
          [[parsed, min].max, max].min
        end

        def clamped_decimal(value, default:, min:, max:)
          parsed = BigDecimal(value.to_s.strip.presence || default.to_s)
          [[parsed, BigDecimal(min.to_s)].max, BigDecimal(max.to_s)].min
        rescue ArgumentError
          default
        end
      end
    end
  end
end
