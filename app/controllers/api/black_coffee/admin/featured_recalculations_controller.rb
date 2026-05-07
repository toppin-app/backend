module Api
  module BlackCoffee
    module Admin
      class FeaturedRecalculationsController < BaseController
        skip_before_action :authenticate_user!, if: :cron_token_request?
        before_action :authorize_request!

        def create
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
      end
    end
  end
end
