require 'set'

class BlackCoffeeFeaturedRecalculator
  RUNNING_CACHE_KEY = 'black_coffee_featured_recalculation_running'.freeze
  CACHE_LOCK_TTL = 15.minutes

  class AlreadyRunningError < StandardError; end

  def self.call(logger: Rails.logger)
    new(logger: logger).call
  end

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def call
    raise AlreadyRunningError, 'Ya hay una recalculacion de destacados Black Coffee en curso.' if Rails.cache.read(RUNNING_CACHE_KEY)

    Rails.cache.write(RUNNING_CACHE_KEY, true, expires_in: CACHE_LOCK_TTL)
    log_info('Inicio de recalculacion de destacados Black Coffee.')

    grouped_rankings = Hash.new { |hash, key| hash[key] = [] }
    state_keys = Set.new
    categories = Set.new
    evaluated_places = 0

    favorites_scope.find_each(batch_size: 1_000) do |row|
      category = row.category.to_s.strip.presence
      next if category.blank?

      state_key = BlackCoffeeVenueCombinationMatrix.normalize_state_key(row.state)
      favorites_count = row.read_attribute(:favorites_count).to_i

      state_keys << state_key
      categories << category
      grouped_rankings[[state_key, category]] << [row.id, favorites_count]
      evaluated_places += 1
    end

    featured_ids = grouped_rankings.values.flat_map do |entries|
      entries.sort_by { |venue_id, favorites_count| [-favorites_count, venue_id.to_s] }
             .first(3)
             .map(&:first)
    end.uniq

      combinations_processed = grouped_rankings.size
    featured_marked = 0

    Venue.transaction do
      clear_current_featured!
      featured_marked = mark_featured!(featured_ids)
    end

    result = {
      success: true,
      evaluated_places: evaluated_places,
      regions_found: state_keys.size,
      categories_found: categories.size,
      combinations_processed: combinations_processed,
      featured_places_marked: featured_marked,
      message: 'Featured Black Coffee places recalculated successfully'
    }

    log_info(
      "Recalculo completado. locales=#{evaluated_places}, regiones=#{state_keys.size}, categorias=#{categories.size}, combinaciones=#{combinations_processed}, destacados=#{featured_marked}"
    )

    result
  rescue StandardError => e
    log_error("Error recalculando destacados Black Coffee: #{e.class} - #{e.message}")
    raise
  ensure
    Rails.cache.delete(RUNNING_CACHE_KEY)
  end

  private

  def favorites_scope
    Venue.public_catalog_scope
         .left_joins(:user_favorites)
         .select('venues.id, venues.state, venues.category, COUNT(user_favorites.id) AS favorites_count')
         .group('venues.id, venues.state, venues.category')
         .order('venues.id ASC')
  end

  def clear_current_featured!
    update_attributes = { featured: false }
    update_attributes[:updated_at] = Time.current if Venue.column_names.include?('updated_at')
    Venue.where(featured: true).update_all(update_attributes)
  end

  def mark_featured!(venue_ids)
    return 0 if venue_ids.empty?

    update_attributes = { featured: true }
    update_attributes[:updated_at] = Time.current if Venue.column_names.include?('updated_at')
    Venue.where(id: venue_ids).update_all(update_attributes)
  end

  def log_info(message)
    @logger.info("[BlackCoffeeFeaturedRecalculator] #{message}")
  end

  def log_error(message)
    @logger.error("[BlackCoffeeFeaturedRecalculator] #{message}")
  end
end
