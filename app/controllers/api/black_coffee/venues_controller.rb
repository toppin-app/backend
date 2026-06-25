module Api
  module BlackCoffee
    class VenuesController < BaseController
      before_action :set_venue, only: [:show, :favorite]

      def index
        category = validated_category(params[:category], allow_all: true)
        return if performed?

        relation = visible_venues
        relation = Venue.filter_by_category(relation, category)
        relation = filter_by_subcategory_for_category(relation, category, params[:subcategory])
        relation = apply_distance_filter_for_category(relation, category)
        return if performed?

        relation = Venue.order_by_favorites(relation.order(featured: :desc)).order(created_at: :desc)
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
        relation = visible_venues.where(featured: true)
        relation = apply_distance_filter(relation)
        return if performed?

        relation = Venue.order_by_favorites(relation).order(created_at: :desc)

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: limit))
        }
      end

      def nearby
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = Venue.filter_by_category(visible_venues, category)

        if Venue.non_geographic_category?(category)
          # Festivals are nationwide events: "nearby" has no meaning, so we return
          # them ordered by popularity instead of requiring coordinates/proximity.
          relation = Venue.order_by_favorites(relation).order(created_at: :desc)
        else
          lat = parse_latitude(required: true)
          lng = parse_longitude(required: true)
          if lat.nil? || lng.nil?
            render json: { error: 'lat and lng are required' }, status: :bad_request
            return
          end

          relation = Venue.within_distance(relation, lat, lng, parse_max_distance)
                          .order(Arel.sql('distance_km ASC'))
        end

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: parse_limit(8, max_value: 50)))
        }
      end

      def popular
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = visible_venues
        relation = Venue.filter_by_category(relation, category)
        relation = apply_distance_filter_for_category(relation, category)
        return if performed?

        relation = Venue.order_by_favorites(relation).order(created_at: :desc)

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: parse_limit(8, max_value: 50)))
        }
      end

      def favorites
        relation = visible_venues.where(id: current_user.user_favorites.select(:venue_id))
        relation = apply_distance_filter(relation)
        return if performed?

        relation = relation.order(Arel.sql(favorite_created_at_order_sql))
        limit = parse_limit(50, max_value: 100)
        offset = parse_offset

        render json: {
          venues: serialize_venues(fetch_venues(relation, limit: limit, offset: offset)),
          total: relation.distinct.count(:id),
          limit: limit,
          offset: offset
        }
      end

      def category
        category = validated_category(params[:category], allow_all: false)
        return if performed?

        relation = Venue.filter_by_category(visible_venues, category)
        relation = filter_by_subcategory_for_category(relation, category, params[:subcategory])
        relation = apply_distance_filter_for_category(relation, category)
        return if performed?

        relation = Venue.order_by_favorites(relation.order(featured: :desc)).order(created_at: :desc)

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
            favorite_venue_ids: favorite_venue_ids_for([@venue]),
            favorite_counts_by_venue_id: Venue.favorite_counts_for([@venue.id]),
            base_url: public_base_url
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

          current_user.user_favorites.create!(venue: @venue)

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

        favorite.destroy!

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
        @venue = visible_venues.includes(:venue_subcategory, :venue_images, :venue_schedules).find_by(id: params[:id])
      end

      def visible_venues
        # TODO: Temporalmente permitimos locales pending en la app mientras se completa la revision inicial.
        # En produccion/futuro, la API deberia devolver solo locales approved.
        Venue.visible_to_app.not_rejected_for_app
      end

      # Festivals (and other destination categories) are nationwide events, so we
      # never drop them for being far away or lacking coordinates. Only local
      # categories are proximity-filtered.
      def apply_distance_filter_for_category(relation, category)
        return relation if Venue.non_geographic_category?(category)

        apply_distance_filter(relation)
      end

      # Non-geographic categories (festivals) are not subcategorised, so a stray
      # subcategory param would inner-join them down to zero. Ignore it for them.
      def filter_by_subcategory_for_category(relation, category, subcategory)
        return relation if Venue.non_geographic_category?(category)

        Venue.filter_by_subcategory(relation, subcategory)
      end

      def apply_distance_filter(relation)
        lat_present = first_present_param(:lat, :latitude, :userLat, :user_lat, :currentLat, :currentLatitude).present?
        lng_present = first_present_param(:lng, :lon, :longitude, :userLng, :user_lng, :currentLng, :currentLongitude).present?
        return relation unless lat_present || lng_present

        lat = parse_latitude(required: true)
        lng = parse_longitude(required: true)
        if lat.nil? || lng.nil?
          render json: { error: 'lat and lng must be valid numbers' }, status: :bad_request
          return relation
        end

        Venue.within_distance(relation, lat, lng, parse_max_distance)
      end

      def favorite_action_param
        request.request_parameters['action'].presence || params[:favorite_action].presence
      end

      def favorite_created_at_order_sql
        <<~SQL.squish
          (
            SELECT user_favorites.created_at
            FROM user_favorites
            WHERE user_favorites.venue_id = venues.id
              AND user_favorites.user_id = #{current_user.id.to_i}
            LIMIT 1
          ) DESC
        SQL
      end
    end
  end
end
