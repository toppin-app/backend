module Api
  module BlackCoffee
    class BaseController < ApplicationController
      respond_to :json
      prepend_before_action :force_json_format

      private

      def force_json_format
        request.format = :json
      end

      def require_admin!
        return if current_user&.admin?

        render json: { error: 'Admin access required' }, status: :forbidden
      end

      def parse_limit(default_value, max_value: 100)
        value = params[:limit].presence || default_value
        [[value.to_i, 1].max, max_value].min
      end

      def parse_offset(default_value = 0)
        [params[:offset].presence.to_i, default_value].max
      end

      def parse_float_param(keys, required: false)
        raw_value = first_present_param(*Array(keys))
        return nil if raw_value.blank? && !required

        Float(raw_value)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_max_distance(default_value = 25.0)
        raw_value =
          first_present_param(
            :maxDistanceKm,
            :max_distance_km,
            :maxDistance,
            :max_distance,
            :radiusKm,
            :radius_km,
            :radius,
            :distanceKm,
            :distance_km,
            :distanceRange,
            :distance_range
          ) || default_value
        distance = raw_value.to_f
        distance.positive? ? distance : default_value
      end

      def parse_latitude(required: false)
        parse_float_param([:lat, :latitude, :userLat, :user_lat, :currentLat, :currentLatitude], required: required)
      end

      def parse_longitude(required: false)
        parse_float_param([:lng, :lon, :longitude, :userLng, :user_lng, :currentLng, :currentLongitude], required: required)
      end

      def validated_category(value, allow_all: false)
        normalized_value = Venue.normalize_text(value)
        return nil if normalized_value.blank?
        return 'all' if allow_all && normalized_value == 'all'
        return normalized_value if Venue::CATEGORIES.include?(normalized_value)

        render json: {
          error: 'Invalid category',
          allowedCategories: Venue::CATEGORIES
        }, status: :unprocessable_entity
        nil
      end

      def fetch_venues(relation, limit:, offset: 0)
        ordered_records = relation.distinct.offset(offset).limit(limit).to_a
        ordered_ids = ordered_records.map(&:id)
        return [] if ordered_ids.empty?

        venues_by_id = Venue.includes(:venue_subcategory, :venue_images, :venue_schedules)
                            .where(id: ordered_ids)
                            .index_by(&:id)

        ordered_ids.map { |id| venues_by_id[id] }.compact
      end

      def favorite_venue_ids_for(venues)
        venue_ids = Array(venues).map(&:id)
        return [] if venue_ids.empty?

        current_user.user_favorites.where(venue_id: venue_ids).pluck(:venue_id)
      end

      def serialize_venues(venues)
        venue_ids = venues.map(&:id)
        favorite_ids = favorite_venue_ids_for(venues)
        favorite_counts = Venue.favorite_counts_for(venue_ids)
        venues.map do |venue|
          venue.as_black_coffee_json(
            favorite_venue_ids: favorite_ids,
            favorite_counts_by_venue_id: favorite_counts,
            base_url: public_base_url
          )
        end
      end

      def public_base_url
        request.base_url.presence || "https://#{ENV['MAILJET_DEFAULT_URL_HOST'] || 'web-backend-ruby.uao3jo.easypanel.host'}"
      end

      def first_present_param(*keys)
        Array(keys).each do |key|
          value = params[key]
          return value if value.present?
        end

        nil
      end
    end
  end
end
