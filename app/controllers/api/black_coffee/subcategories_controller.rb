module Api
  module BlackCoffee
    class SubcategoriesController < BaseController
      before_action :require_admin!
      before_action :set_subcategory, only: [:update, :destroy]

      def index
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = VenueSubcategory.left_joins(:venues)
        relation = relation.where(category: category) if category.present?

        subcategories = relation.group('venue_subcategories.id')
                                .order(:category, :name)
                                .select('venue_subcategories.*, COUNT(venues.id) AS venues_count')

        render json: {
          subcategories: subcategories.map do |subcategory|
            {
              id: subcategory.id,
              name: subcategory.name,
              category: subcategory.category,
              venueCount: subcategory.try(:venues_count).to_i
            }
          end
        }
      end

      def create
        @subcategory = VenueSubcategory.new(subcategory_params)

        if @subcategory.save
          render json: {
            subcategory: @subcategory.as_black_coffee_json
          }, status: :created
        else
          render json: { errors: @subcategory.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        unless @subcategory
          render json: { error: 'Subcategory not found' }, status: :not_found
          return
        end

        if @subcategory.update(update_subcategory_params)
          render json: {
            subcategory: @subcategory.as_black_coffee_json
          }
        else
          render json: { errors: @subcategory.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        unless @subcategory
          render json: { error: 'Subcategory not found' }, status: :not_found
          return
        end

        @subcategory.destroy
        render json: { success: true }
      end

      private

      def set_subcategory
        @subcategory = VenueSubcategory.find_by(id: params[:id])
      end

      def subcategory_params
        payload = params[:subcategory].presence || params
        payload.permit(:name, :category)
      end

      def update_subcategory_params
        payload = params[:subcategory].presence || params
        payload.permit(:name)
      end
    end
  end
end
