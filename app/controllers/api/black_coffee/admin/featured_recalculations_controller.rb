module Api
  module BlackCoffee
    module Admin
      class FeaturedRecalculationsController < BaseController
        skip_before_action :authenticate_user!, if: :cron_token_request?
        before_action :authorize_request!

        def create
          if cron_token_request?
            handle_cron_request
            return
          end

          result = BlackCoffeeFeaturedRecalculator.call
          render json: result
        rescue BlackCoffeeFeaturedRecalculator::AlreadyRunningError => e
          render json: {
            success: false,
            error: e.message
          }, status: :conflict
        rescue StandardError => e
          render json: {
            success: false,
            error: e.message,
            message: 'Featured Black Coffee places recalculation failed'
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

        def handle_cron_request
          enqueue_result = BlackCoffeeFeaturedRecalculator.enqueue!

          case enqueue_result
          when :started
            render json: {
              success: true,
              queued: true,
              running: true,
              message: 'Featured Black Coffee recalculation started'
            }, status: :ok
          when :already_running
            render json: {
              success: true,
              queued: false,
              running: true,
              message: 'Featured Black Coffee recalculation already running',
              last_result: BlackCoffeeFeaturedRecalculator.last_result
            }, status: :ok
          else
            render json: {
              success: true,
              queued: false,
              running: BlackCoffeeFeaturedRecalculator.running?,
              message: 'Featured Black Coffee recalculation request accepted',
              last_result: BlackCoffeeFeaturedRecalculator.last_result
            }, status: :ok
          end
        end
      end
    end
  end
end
