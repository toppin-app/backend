class AnalyticsService
  # Filter parameters helper
  # Filters are OPTIONAL and ADDITIVE - only apply when explicitly set
  def self.apply_filters(scope, filters)
    Rails.logger.debug "ANALYTICS SERVICE - apply_filters called with:"
    Rails.logger.debug "  filters: #{filters.inspect}"
    Rails.logger.debug "  initial scope SQL: #{scope.to_sql}" rescue nil
    
    # Account status filters (mutually exclusive)
    if filters[:exclude_deleted] == true
      scope = scope.where(deleted_account: false)
    elsif filters[:only_deleted] == true
      scope = scope.where(deleted_account: true)
    end
    # If both are false or nil, show ALL accounts
    
    # Bot filters (mutually exclusive)
    if filters[:exclude_bots] == true
      scope = scope.where(fake_user: false)
    elsif filters[:only_bots] == true
      scope = scope.where(fake_user: true)
    end
    # If both are false or nil, show ALL users (bots and real)
    
    # Optional filters - only apply when explicitly set
    scope = scope.where(gender: filters[:gender]) if filters[:gender].present?
    scope = scope.where(device_platform: filters[:device_platform]) if filters[:device_platform].present?
    scope = scope.where(verified: true) if filters[:verified] == true
    scope = scope.where(verified: false) if filters[:verified] == false
    scope = scope.where('location_country = ?', filters[:country]) if filters[:country].present?
    scope = scope.where('location_city = ?', filters[:city]) if filters[:city].present?
    
    # Subscription filter
    if filters[:subscription_type].present?
      case filters[:subscription_type]
      when 'free'
        scope = scope.where(current_subscription_name: nil)
      when 'premium'
        scope = scope.where(current_subscription_name: 'premium')
      when 'supreme'
        scope = scope.where(current_subscription_name: 'supreme')
      end
    end
    
    # NOTE: Date filtering is handled by apply_date_range only
    # Do NOT filter by dates here to avoid double filtering
    
    Rails.logger.debug "ANALYTICS SERVICE - Final filtered scope SQL:"
    Rails.logger.debug scope.to_sql rescue "Could not generate SQL"
    Rails.logger.debug "="*80
    
    scope
  end

  # ===== GROWTH METRICS =====
  
  def self.new_users_over_time(filters = {}, group_by = :day)
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    case group_by
    when :day
      scope.group("DATE(created_at)").count
    when :week
      scope.group("YEARWEEK(created_at)").count
    when :month
      scope.group("DATE_FORMAT(created_at, '%Y-%m')").count
    end
  end

  def self.cumulative_users(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    users_by_day = scope.group("DATE(created_at)").count
    cumulative = {}
    total = 0
    users_by_day.sort.each do |date, count|
      total += count
      cumulative[date.to_s] = total
    end
    cumulative
  end

  def self.user_count_metrics(filters = {})
    # CORRECT PATTERN: User.all → apply_filters → apply_date_range
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    # ALL metrics use the filtered scope
    total_users = scope.count
    
    # Breakdown by type - counts within filtered dataset
    # Note: If user selected "Only Bots", real_users will be 0
    # Note: If user selected "Exclude Bots", bot_users will be 0
    real_users = scope.where(fake_user: false, deleted_account: false).count
    bot_users = scope.where(fake_user: true).count
    verified_users = scope.where(verified: true, deleted_account: false).count
    deleted_users = scope.where(deleted_account: true).count
    
    {
      total_users: total_users,
      real_users: real_users,
      bot_users: bot_users,
      verified_users: verified_users,
      deleted_users: deleted_users
    }
  end

  def self.users_by_type(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    # Apply ALL filters to get the base filtered dataset
    # Then break it down by type
    filtered_scope = apply_filters(scope, filters)
    
    # Count each type within the filtered dataset
    # If user excluded bots, bots count will be 0
    # If user excluded deleted, deleted count will be 0
    {
      real: filtered_scope.where(fake_user: false, deleted_account: false).count,
      bots: filtered_scope.where(fake_user: true).count,
      deleted: filtered_scope.where(deleted_account: true).count
    }
  end

  def self.verified_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    {
      verified: scope.where(verified: true).count,
      non_verified: scope.where(verified: false).count
    }
  end

  def self.deletions_over_time(filters = {})
    # Start with all users, apply filters, then restrict to deleted
    scope = User.all
    scope = apply_filters(scope, filters)
    # Only show deletions (but respecting other filters like gender, country, etc)
    scope = scope.where(deleted_account: true)
    scope = apply_date_range(scope, filters, :updated_at)
    
    scope.group("DATE(updated_at)").count
  end

  # ===== ENGAGEMENT METRICS =====
  
  def self.daily_active_users(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :last_sign_in_at)
    
    scope.group("DATE(last_sign_in_at)").count
  end

  def self.engagement_metrics(filters = {})
    base_scope = User.all
    base_scope = apply_filters(base_scope, filters)
    date_range = get_date_range(filters)
    
    dau = base_scope.where('last_sign_in_at >= ?', date_range[:start]).count
    wau = base_scope.where('last_sign_in_at >= ?', date_range[:wau_start]).count
    mau = base_scope.where('last_sign_in_at >= ?', date_range[:mau_start]).count
    
    {
      dau: dau,
      wau: wau,
      mau: mau,
      dau_mau_ratio: mau > 0 ? (dau.to_f / mau * 100).round(2) : 0
    }
  end

  def self.likes_sent_over_time(filters = {})
    # Apply user filters first
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    # Then get match requests from filtered users
    scope = UserMatchRequest.where(from_user_id: user_ids)
    scope = apply_date_range(scope, filters, :created_at)
    
    scope.group("DATE(created_at)").count
  end

  def self.matches_created_over_time(filters = {})
    # Apply user filters first
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    # Then get matches from filtered users
    scope = UserMatchRequest.where(is_match: true).where(from_user_id: user_ids)
    scope = apply_date_range(scope, filters, :match_date)
    
    scope.group("DATE(match_date)").count
  end

  def self.average_engagement(filters = {})
    base_scope = User.all
    scope = apply_filters(base_scope, filters)
    
    total_users = scope.count
    return {} if total_users == 0
    
    {
      avg_matches: scope.average(:matches_number).to_f.round(2),
      avg_likes_received: scope.average(:incoming_likes_number).to_f.round(2),
      avg_ratio_likes: scope.average(:ratio_likes).to_f.round(2)
    }
  end
  
  # ===== DEMOGRAPHICS =====
  
  def self.gender_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters.except(:gender))
    scope = apply_date_range(scope, filters, :created_at)
    
    scope.group(:gender).count
  end

  def self.age_distribution(filters = {})
    # Start with all users, apply filters properly
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without birthday AFTER applying user filters
    scope = scope.where.not(birthday: nil)
    
    users = scope.select(:birthday)
    age_groups = { '18-24' => 0, '25-34' => 0, '35-44' => 0, '45-54' => 0, '55+' => 0 }
    
    users.each do |user|
      age = ((Time.current - user.birthday.to_time) / 1.year).to_i
      case age
      when 18..24 then age_groups['18-24'] += 1
      when 25..34 then age_groups['25-34'] += 1
      when 35..44 then age_groups['35-44'] += 1
      when 45..54 then age_groups['45-54'] += 1
      else age_groups['55+'] += 1 if age >= 55
      end
    end
    
    age_groups
  end

  def self.top_countries(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters.except(:country))
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without country AFTER applying filters
    scope = scope.where.not(location_country: nil)
    
    scope.group(:location_country).count.sort_by { |_, v| -v }.first(limit).to_h
  end

  def self.top_cities(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters.except(:city))
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without city AFTER applying filters
    scope = scope.where.not(location_city: nil)
    
    scope.group(:location_city).count.sort_by { |_, v| -v }.first(limit).to_h
  end

  def self.average_age_by_gender(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without birthday AFTER applying filters
    scope = scope.where.not(birthday: nil)
    
    result = {}
    User.genders.keys.each do |gender|
      users = scope.where(gender: gender)
      if users.any?
        avg_age = users.average("TIMESTAMPDIFF(YEAR, birthday, CURDATE())").to_f.round(1)
        result[gender] = avg_age
      end
    end
    result
  end

  # ===== MATCHING SYSTEM =====
  
  def self.match_metrics(filters = {})
    # Apply user filters first
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    date_range = get_date_range(filters)
    
    # Get match requests from filtered users only
    total_likes = UserMatchRequest.where(from_user_id: user_ids).where('created_at >= ?', date_range[:start]).count
    total_superlikes = UserMatchRequest.where(from_user_id: user_ids).where('created_at >= ? AND is_superlike = ?', date_range[:start], true).count
    total_matches = UserMatchRequest.where(from_user_id: user_ids).where('is_match = ? AND match_date >= ?', true, date_range[:start]).count
    
    conversion_rate = total_likes > 0 ? (total_matches.to_f / total_likes * 100).round(2) : 0
    superlike_conversion = total_superlikes > 0 ? (UserMatchRequest.where(from_user_id: user_ids).where('is_match = ? AND is_superlike = ? AND match_date >= ?', true, true, date_range[:start]).count.to_f / total_superlikes * 100).round(2) : 0
    
    {
      total_likes: total_likes,
      total_superlikes: total_superlikes,
      total_matches: total_matches,
      conversion_rate: conversion_rate,
      superlike_conversion_rate: superlike_conversion
    }
  end

  def self.matches_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    
    distribution = { '0' => 0, '1-5' => 0, '6-20' => 0, '21-50' => 0, '51-100' => 0, '100+' => 0 }
    
    scope.select(:matches_number).each do |user|
      matches = user.matches_number || 0
      case matches
      when 0 then distribution['0'] += 1
      when 1..5 then distribution['1-5'] += 1
      when 6..20 then distribution['6-20'] += 1
      when 21..50 then distribution['21-50'] += 1
      when 51..100 then distribution['51-100'] += 1
      else distribution['100+'] += 1
      end
    end
    
    distribution
  end

  # ===== MONETIZATION =====
  
  def self.subscription_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters.except(:subscription_type))
    scope = apply_date_range(scope, filters, :created_at)
    
    {
      free: scope.where(current_subscription_name: nil).count,
      premium: scope.where(current_subscription_name: 'premium').count,
      supreme: scope.where(current_subscription_name: 'supreme').count
    }
  end

  def self.revenue_over_time(filters = {})
    return {} unless table_exists?('purchases')
    
    # Apply user filters
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    scope = Purchase.where(user_id: user_ids)
    scope = apply_date_range(scope, filters, 'created_at')
    
    scope.group("DATE(created_at)").sum(:price)
  end

  def self.revenue_metrics(filters = {})
    return default_revenue_metrics unless table_exists?('purchases')
    
    date_range = get_date_range(filters)
    
    # Apply user filters to purchases through joins
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    purchases = Purchase.where(user_id: user_ids)
    purchases = purchases.where('purchases.created_at >= ?', date_range[:start]) if date_range[:start].present?
    total_revenue = purchases.sum(:price)
    
    total_users = user_scope.count
    paying_users = user_scope.where.not(current_subscription_name: nil).count
    
    {
      total_revenue: total_revenue,
      arpu: total_users > 0 ? (total_revenue.to_f / total_users).round(2) : 0,
      arppu: paying_users > 0 ? (total_revenue.to_f / paying_users).round(2) : 0,
      paying_users: paying_users,
      conversion_rate: total_users > 0 ? (paying_users.to_f / total_users * 100).round(2) : 0
    }
  end

  def self.platform_revenue(filters = {})
    return {} unless table_exists?('purchases')
    
    date_range = get_date_range(filters)
    
    # Apply user filters
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    
    Purchase.joins(:user)
      .where(user_id: user_scope.select(:id))
      .where('purchases.created_at >= ?', date_range[:start])
      .group('users.device_platform')
      .sum(:price)
  end

  def self.boost_superlike_usage(filters = {})
    date_range = get_date_range(filters)
    scope = User.all
    scope = apply_filters(scope, filters)
    
    # This is approximate - you might want to track actual usage in a separate table
    {
      boost_usage: scope.where('boost_available > ?', 0).count,
      superlike_usage: scope.where('superlike_available > ?', 0).count
    }
  end

  # ===== RETENTION =====
  
  def self.retention_cohorts(filters = {})
    # Simplified cohort analysis - users grouped by signup month
    cohorts = {}
    
    # Apply user filters to base scope
    base_scope = User.all
    base_scope = apply_filters(base_scope, filters.except(:start_date, :end_date))
    
    # Get users from last 6 months
    6.downto(0).each do |months_ago|
      cohort_start = months_ago.months.ago.beginning_of_month
      cohort_end = cohort_start.end_of_month
      
      cohort_users = base_scope.where(created_at: cohort_start..cohort_end)
      cohort_size = cohort_users.count
      
      next if cohort_size == 0
      
      # Calculate retention for each subsequent day/week
      retention = {}
      [1, 7, 30].each do |days|
        target_date = cohort_start + days.days
        break if target_date > Time.current
        
        retained = cohort_users.where('last_sign_in_at >= ?', target_date).count
        retention["day_#{days}"] = cohort_size > 0 ? (retained.to_f / cohort_size * 100).round(2) : 0
      end
      
      cohorts[cohort_start.strftime('%Y-%m')] = {
        size: cohort_size,
        retention: retention
      }
    end
    
    cohorts
  end

  def self.churn_metrics(filters = {})
    date_range = get_date_range(filters)
    
    # Apply user filters first
    scope = User.all
    scope = apply_filters(scope, filters)
    
    total_users = scope.where('created_at < ?', date_range[:start]).count
    churned_users = scope.where('created_at < ? AND (deleted_account = ? OR last_sign_in_at < ?)', 
                                date_range[:start], true, 30.days.ago).count
    
    {
      total_users: total_users,
      churned_users: churned_users,
      churn_rate: total_users > 0 ? (churned_users.to_f / total_users * 100).round(2) : 0
    }
  end

  # ===== TOP INSIGHTS =====
  
  def self.top_users(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters)
    
    {
      most_matches: scope.order(matches_number: :desc).limit(limit).pluck(:id, :name, :matches_number),
      most_liked: scope.order(incoming_likes_number: :desc).limit(limit).pluck(:id, :name, :incoming_likes_number),
      highest_ranking: scope.order(ranking: :desc).limit(limit).pluck(:id, :name, :ranking)
    }
  end

  def self.top_performing_cities(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters.except(:city))
    scope = scope.where.not(location_city: nil)
    
    cities = scope.group(:location_city).count.sort_by { |_, v| -v }.first(limit)
    
    city_stats = cities.map do |city, count|
      city_users = scope.where(location_city: city)
      avg_matches = city_users.average(:matches_number).to_f.round(2)
      
      {
        city: city,
        users: count,
        avg_matches: avg_matches
      }
    end
    
    city_stats
  end
  
  def self.table_exists?(table_name)
    ActiveRecord::Base.connection.table_exists?(table_name)
  end
  
  def self.default_revenue_metrics
    {
      total_revenue: 0,
      arpu: 0,
      arppu: 0,
      paying_users: 0,
      conversion_rate: 0
    }
  end

  # ===== HELPER METHODS =====
  
  private
  
  def self.apply_date_range(scope, filters, column)
    if filters[:start_date].present? && filters[:end_date].present?
      scope.where("#{column} >= ? AND #{column} <= ?", filters[:start_date], filters[:end_date])
    else
      scope
    end
  end

  def self.get_date_range(filters)
    if filters[:start_date].present? && filters[:end_date].present?
      { 
        start: filters[:start_date], 
        end: filters[:end_date],
        wau_start: [filters[:start_date], 7.days.ago].max,
        mau_start: [filters[:start_date], 30.days.ago].max
      }
    else
      # Default to reasonable ranges for engagement metrics
      { 
        start: 1.day.ago,  # DAU - last 24 hours
        wau_start: 7.days.ago,   # WAU - last 7 days
        mau_start: 30.days.ago,  # MAU - last 30 days
        end: Time.current 
      }
    end
  end
end
