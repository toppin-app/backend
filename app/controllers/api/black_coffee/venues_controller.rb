module Api
  module BlackCoffee
    class VenuesController < BaseController
      before_action :set_venue, only: [:show, :favorite]

      def index
        category = validated_category(params[:category], allow_all: true)
        return if performed?

        relation = Venue.all
        relation = Venue.filter_by_category(relation, category)
        relation = Venue.filter_by_subcategory(relation, params[:subcategory])
        relation = apply_distance_filter(relation)
        return if performed?

        relation = relation.order(featured: :desc, favorites_count: :desc, created_at: :desc)
        limit = parse_limit(50)
        offset = parse_offset

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: limit, offset: offset)),
          total: relation.distinct.count(:id),
          limit: limit,
          offset: offset
        }
      end

      def featured
        limit = parse_limit(5, max_value: 20)
        relation = Venue.where(featured: true).order(favorites_count: :desc, created_at: :desc)

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: limit))
        }
      end

      def nearby
        lat = parse_float_param(:lat, required: true)
        lng = parse_float_param(:lng, required: true)
        if lat.nil? || lng.nil?
          render json: { error: 'lat and lng are required' }, status: :bad_request
          return
        end

        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = Venue.all
        relation = Venue.filter_by_category(relation, category)
        relation = Venue.within_distance(relation, lat, lng, parse_max_distance)
                        .order(Arel.sql('distance_km ASC'))

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: parse_limit(8, max_value: 50)))
        }
      end

      def popular
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = Venue.all
        relation = Venue.filter_by_category(relation, category)
        relation = relation.order(favorites_count: :desc, created_at: :desc)

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: parse_limit(8, max_value: 50)))
        }
      end

      def category
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = Venue.filter_by_category(Venue.all, category)
        relation = Venue.filter_by_subcategory(relation, params[:subcategory])
                        .order(featured: :desc, favorites_count: :desc, created_at: :desc)

        limit = parse_limit(20)
        offset = parse_offset

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: limit, offset: offset)),
          total: relation.distinct.count(:id),
          limit: limit,
          offset: offset
        }
      end

      def show
        unless @venue
          render json: {
            error: 'Venue not found',
            venueId: params[:id]
          }, status: :not_found
          return
        end

        render json: {
          venue: @venue.as_black_coffee_json(
            favorite_venue_ids: favorite_venue_ids_for([@venue])
          )
        }
      end

      def favorite
        unless @venue
          render json: {
            error: 'Venue not found',
            venueId: params[:id]
          }, status: :not_found
          return
        end

        requested_action = favorite_action_param
        unless %w[add remove].include?(requested_action)
          render json: { success: false, error: 'Invalid action' }, status: :unprocessable_entity
          return
        end

        favorite = current_user.user_favorites.find_by(venue_id: @venue.id)

        if requested_action == 'add'
          if favorite.present?
            render json: {
              success: false,
              error: 'Already favorited',
              isFavorite: true,
              currentCount: @venue.favorites_count
            }, status: :conflict
            return
          end

          UserFavorite.transaction do
            current_user.user_favorites.create!(venue: @venue)
            Venue.where(id: @venue.id).update_all('favorites_count = COALESCE(favorites_count, 0) + 1')
          end

          @venue.reload
          render json: {
            success: true,
            isFavorite: true,
            newCount: @venue.favorites_count
          }
          return
        end

        if favorite.blank?
          render json: {
            success: false,
            error: 'Already not favorited',
            isFavorite: false,
            currentCount: @venue.favorites_count
          }, status: :conflict
          return
        end

        UserFavorite.transaction do
          favorite.destroy!
          Venue.where(id: @venue.id)
               .update_all('favorites_count = CASE WHEN favorites_count > 0 THEN favorites_count - 1 ELSE 0 END')
        end

        @venue.reload
        render json: {
          success: true,
          isFavorite: false,
          newCount: @venue.favorites_count
        }
      rescue ActiveRecord::RecordInvalid => e
        render json: { success: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      private

      def set_venue
        @venue = Venue.includes(:venue_subcategory, :venue_images, :venue_schedules).find_by(id: params[:id])
      end

      def apply_distance_filter(relation)
        lat_present = params[:lat].present?
        lng_present = params[:lng].present?
        return relation unless lat_present || lng_present

        lat = parse_float_param(:lat, required: true)
        lng = parse_float_param(:lng, required: true)
        if lat.nil? || lng.nil?
          render json: { error: 'lat and lng must be valid numbers' }, status: :bad_request
          return relation
        end

        Venue.within_distance(relation, lat, lng, parse_max_distance)
      end

      def favorite_action_param
        request.request_parameters['action'].presence || params[:favorite_action].presence
      end
    end
  end
end
