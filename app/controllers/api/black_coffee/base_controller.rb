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

      def parse_float_param(key, required: false)
        raw_value = params[key]
        return nil if raw_value.blank? && !required

        Float(raw_value)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_max_distance(default_value = 25.0)
        raw_value = params[:maxDistanceKm].presence || default_value
        distance = raw_value.to_f
        distance.positive? ? distance : default_value
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
        favorite_ids = favorite_venue_ids_for(venues)
        venues.map { |venue| venue.as_black_coffee_json(favorite_venue_ids: favorite_ids) }
      end
    end
  end
end
