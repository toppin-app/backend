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
        relation = apply_publication_rules_for_category(relation, category)
        relation = apply_event_filters_for_category(relation, category)
        relation = apply_distance_filter_for_category(relation, category)
        return if performed?

        relation = order_for_category(relation, category)
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
          # Destination event categories are nationwide: "nearby" has no meaning,
          # so we return them ordered by popularity instead of requiring proximity.
          relation = apply_publication_rules_for_category(relation, category)
          relation = apply_event_filters_for_category(relation, category)
          relation = order_for_category(relation, category)
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
        relation = apply_publication_rules_for_category(relation, category)
        relation = apply_event_filters_for_category(relation, category)
        relation = apply_distance_filter_for_category(relation, category)
        return if performed?

        relation = order_for_category(relation, category)

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
        relation = apply_publication_rules_for_category(relation, category)
        relation = apply_event_filters_for_category(relation, category)
        relation = apply_distance_filter_for_category(relation, category)
        return if performed?

        relation = order_for_category(relation, category)

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
        # Los conciertos ya aplican la regla futura: solo approved, visibles y no ocurridos.
        apply_concert_visibility_rules(Venue.visible_to_app.not_rejected_for_app)
      end

      def apply_concert_visibility_rules(relation)
        return relation unless Venue.column_names.include?('review_status')

        conditions = ['venues.category <> ? OR (venues.category = ? AND venues.review_status = ?']
        values = ['concierto', 'concierto', Venue::REVIEW_STATUS_APPROVED]

        if Venue.column_names.include?('event_status')
          conditions << 'AND venues.event_status = ?'
          values << Venue::EVENT_STATUS_UPCOMING
        end

        if Venue.column_names.include?('event_start_at') && Venue.column_names.include?('festival_start_date')
          conditions << 'AND COALESCE(venues.event_end_at, venues.event_start_at, venues.festival_end_date, venues.festival_start_date) >= ?'
          values << Time.zone.today
        elsif Venue.column_names.include?('event_start_at')
          conditions << 'AND COALESCE(venues.event_end_at, venues.event_start_at) >= ?'
          values << Time.zone.today.beginning_of_day
        end

        conditions << ')'
        relation.where(conditions.join(' '), *values)
      end

      def apply_publication_rules_for_category(relation, category)
        return relation unless Venue.normalize_category(category) == 'concierto'

        relation.where(category: 'concierto')
      end

      def apply_event_filters_for_category(relation, category)
        return relation unless Venue.normalize_category(category) == 'concierto'

        relation = filter_concerts_by_country(relation)
        relation = filter_concerts_by_city(relation)
        filter_concerts_by_date_range(relation)
      end

      def filter_concerts_by_country(relation)
        country_code = normalized_country_code_param
        return relation if country_code.blank? || !Venue.column_names.include?('country_code')

        relation.where('UPPER(venues.country_code) = ?', country_code)
      end

      def normalized_country_code_param
        country_code = first_present_param(:country_code, :countryCode).to_s.strip.upcase
        country_code if country_code.match?(/\A[A-Z]{2}\z/)
      end

      def filter_concerts_by_city(relation)
        city = params[:city].to_s.strip
        return relation if city.blank?

        relation.where('LOWER(venues.city) = ?', city.downcase)
      end

      def filter_concerts_by_date_range(relation)
        start_date = parse_date_param(:start_date, :from_date, :date)
        end_date = parse_date_param(:end_date, :to_date, :date)
        return relation if start_date.blank? && end_date.blank?

        date_sql = event_date_sql
        relation = relation.where("#{date_sql} >= ?", start_date) if start_date.present?
        relation = relation.where("#{date_sql} <= ?", end_date) if end_date.present?
        relation
      end

      def parse_date_param(*keys)
        raw = first_present_param(*keys)
        return nil if raw.blank?

        Date.iso8601(raw.to_s)
      rescue ArgumentError
        nil
      end

      def event_date_sql
        if Venue.column_names.include?('event_start_at') && Venue.column_names.include?('festival_start_date')
          'DATE(COALESCE(venues.event_start_at, venues.festival_start_date))'
        elsif Venue.column_names.include?('event_start_at')
          'DATE(venues.event_start_at)'
        else
          'venues.festival_start_date'
        end
      end

      def order_for_category(relation, category)
        return concert_order(relation) if Venue.normalize_category(category) == 'concierto'

        Venue.order_by_favorites(relation.order(featured: :desc)).order(created_at: :desc)
      end

      def concert_order(relation)
        if Venue.column_names.include?('event_start_at') && Venue.column_names.include?('festival_start_date')
          relation.order(Arel.sql('COALESCE(venues.event_start_at, venues.festival_start_date) ASC')).order(:name)
        elsif Venue.column_names.include?('festival_start_date')
          relation.order(festival_start_date: :asc).order(:name)
        else
          relation.order(created_at: :desc)
        end
      end

      # Festivals (and other destination categories) are nationwide events, so we
      # never drop them for being far away or lacking coordinates. Only local
      # categories are proximity-filtered.
      def apply_distance_filter_for_category(relation, category)
        return relation if Venue.non_geographic_category?(category)

        apply_distance_filter(relation)
      end

      # Non-geographic event categories are not subcategorised, so a stray
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
