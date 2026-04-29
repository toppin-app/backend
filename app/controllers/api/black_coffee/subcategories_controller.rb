module Api
  module BlackCoffee
    class SubcategoriesController < BaseController
      before_action :require_admin!

      def index
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        counts = Venue.joins(:venue_subcategory)
                      .group('venue_subcategories.category', 'venue_subcategories.name')
                      .count
        subcategories = BlackCoffeeTaxonomy.subcategory_options(category)

        render json: {
          subcategories: subcategories.map do |subcategory|
            {
              id: BlackCoffeeTaxonomy.subcategory_id(subcategory[:category], subcategory[:name]),
              name: subcategory[:name],
              label: subcategory[:label],
              category: subcategory[:category],
              googleTypes: Array(subcategory[:google_types]),
              venueCount: counts[[subcategory[:category], subcategory[:name]]].to_i
            }
          end
        }
      end

      def create
        render json: { error: 'Subcategories are fixed and cannot be created dynamically.' }, status: :method_not_allowed
      end

      def update
        render json: { error: 'Subcategories are fixed and cannot be updated dynamically.' }, status: :method_not_allowed
      end

      def destroy
        render json: { error: 'Subcategories are fixed and cannot be deleted dynamically.' }, status: :method_not_allowed
      end
    end
  end
end
