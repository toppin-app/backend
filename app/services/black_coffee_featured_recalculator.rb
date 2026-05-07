require 'set'

class BlackCoffeeFeaturedRecalculator
  RUNNING_CACHE_KEY = 'black_coffee_featured_recalculation_running'.freeze
  LAST_RESULT_CACHE_KEY = 'black_coffee_featured_recalculation_last_result'.freeze
  CACHE_LOCK_TTL = 15.minutes
  LAST_RESULT_TTL = 7.days

  class AlreadyRunningError < StandardError; end

  def self.call(logger: Rails.logger)
    new(logger: logger).call
  end

  def self.enqueue!(logger: Rails.logger)
    return :already_running if running?

    Rails.cache.write(RUNNING_CACHE_KEY, true, expires_in: CACHE_LOCK_TTL)

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        new(logger: logger, lock_acquired: true).call
      end
    rescue StandardError => e
      logger.error("[BlackCoffeeFeaturedRecalculator] Error en ejecucion asincrona: #{e.class} - #{e.message}")
      Rails.cache.write(
        LAST_RESULT_CACHE_KEY,
        {
          success: false,
          error: e.message,
          message: 'Featured Black Coffee places recalculation failed',
          failed_at: Time.current
        },
        expires_in: LAST_RESULT_TTL
      )
      Rails.cache.delete(RUNNING_CACHE_KEY)
    end

    :started
  rescue StandardError
    Rails.cache.delete(RUNNING_CACHE_KEY)
    raise
  end

  def self.running?
    Rails.cache.read(RUNNING_CACHE_KEY).present?
  end

  def self.last_result
    Rails.cache.read(LAST_RESULT_CACHE_KEY)
  end

  def initialize(logger: Rails.logger, lock_acquired: false)
    @logger = logger
    @lock_acquired = lock_acquired
  end

  def call
    acquire_lock! unless @lock_acquired
    @lock_acquired = true

    result = perform_recalculation
    store_last_result(result)
    result
  rescue StandardError => e
    store_last_result(
      success: false,
      error: e.message,
      message: 'Featured Black Coffee places recalculation failed',
      failed_at: Time.current
    )
    log_error("Error recalculando destacados Black Coffee: #{e.class} - #{e.message}")
    raise
  ensure
    Rails.cache.delete(RUNNING_CACHE_KEY) if @lock_acquired
  end

  private

  def acquire_lock!
    raise AlreadyRunningError, 'Ya hay una recalculacion de destacados Black Coffee en curso.' if self.class.running?

    Rails.cache.write(RUNNING_CACHE_KEY, true, expires_in: CACHE_LOCK_TTL)
  end

  def perform_recalculation
    log_info('Inicio de recalculacion de destacados Black Coffee.')

    grouped_rankings = Hash.new { |hash, key| hash[key] = [] }
    location_keys = Set.new
    categories = Set.new
    evaluated_places = 0

    favorites_scope.find_each(batch_size: 1_000) do |row|
      category = row.category.to_s.strip.presence
      next if category.blank?

      state_key = BlackCoffeeVenueCombinationMatrix.location_key_for(
        city: row.city.to_s.strip,
        state: row.state.to_s.strip
      )
      favorites_count = row.read_attribute(:favorites_count).to_i

      location_keys << state_key
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
      regions_found: location_keys.size,
      location_groups_found: location_keys.size,
      categories_found: categories.size,
      combinations_processed: combinations_processed,
      featured_places_marked: featured_marked,
      completed_at: Time.current,
      message: 'Featured Black Coffee places recalculated successfully'
    }

    log_info(
      "Recalculo completado. locales=#{evaluated_places}, ubicaciones=#{location_keys.size}, categorias=#{categories.size}, combinaciones=#{combinations_processed}, destacados=#{featured_marked}"
    )

    result
  end

  def store_last_result(result)
    Rails.cache.write(LAST_RESULT_CACHE_KEY, result, expires_in: LAST_RESULT_TTL)
  end

  def favorites_scope
    Venue.public_catalog_scope
         .left_joins(:user_favorites)
         .select('venues.id, venues.city, venues.state, venues.category, COUNT(user_favorites.id) AS favorites_count')
         .group('venues.id, venues.city, venues.state, venues.category')
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
