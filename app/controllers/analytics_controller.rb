class AnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :check_admin
  before_action :parse_filters, only: [:index, :data]

  def index
    @title = "User Analytics Dashboard"
    
    # Pre-load key metrics for initial page load
    # DEFAULT: Exclude bots and deleted accounts (show only real active users)
    default_user_scope = User.where(deleted_account: false, fake_user: false)
    
    @key_metrics = {
      total_users: default_user_scope.count,
      total_matches: UserMatchRequest.where(is_match: true).count,
      active_users_today: default_user_scope.where('last_sign_in_at >= ?', 24.hours.ago).count
    }
    
    # Filter options - show ALL countries and cities (no filters)
    @countries = User.where.not(location_country: nil).distinct.pluck(:location_country).sort
    @cities = User.where.not(location_city: nil).distinct.pluck(:location_city).sort
  end

  def data
    section = params[:section]
    
    data = case section
    when 'growth'
      growth_data
    when 'demographics'
      demographics_data
    when 'insights'
      insights_data
    when 'media'
      media_data
    when 'interests'
      interests_data
    when 'spotify'
      spotify_data
    when 'languages'
      languages_data
    when 'complaints'
      complaints_data
    when 'interactions'
      interactions_data
    when 'blocks'
      blocks_data
    when 'invisible_mode'
      invisible_mode_data
    else
      { error: 'Invalid section' }
    end
    
    render json: data
  end

  private

  def parse_filters
    @filters = {}
    
    # Log incoming parameters
    Rails.logger.debug "="*80
    Rails.logger.debug "ANALYTICS FILTERS - Incoming params:"
    Rails.logger.debug "  date_range: #{params[:date_range]}"
    Rails.logger.debug "  bot_filter: #{params[:bot_filter]}"
    Rails.logger.debug "  account_status: #{params[:account_status]}"
    Rails.logger.debug "  gender: #{params[:gender]}"
    Rails.logger.debug "  device_platform: #{params[:device_platform]}"
    Rails.logger.debug "  subscription_type: #{params[:subscription_type]}"
    Rails.logger.debug "  country: #{params[:country]}"
    Rails.logger.debug "  city: #{params[:city]}"
    Rails.logger.debug "  verified: #{params[:verified]}"
    Rails.logger.debug "="*80
    
    # Date range
    case params[:date_range]
    when 'today'
      @filters[:start_date] = Time.current.beginning_of_day
      @filters[:end_date] = Time.current.end_of_day
    when 'yesterday'
      @filters[:start_date] = 1.day.ago.beginning_of_day
      @filters[:end_date] = 1.day.ago.end_of_day
    when 'last_7_days'
      @filters[:start_date] = 7.days.ago.beginning_of_day
      @filters[:end_date] = Time.current.end_of_day
    when 'last_30_days'
      @filters[:start_date] = 30.days.ago.beginning_of_day
      @filters[:end_date] = Time.current.end_of_day
    when 'last_90_days'
      @filters[:start_date] = 90.days.ago.beginning_of_day
      @filters[:end_date] = Time.current.end_of_day
    when 'last_12_months'
      @filters[:start_date] = 12.months.ago.beginning_of_day
      @filters[:end_date] = Time.current.end_of_day
    when 'custom'
      @filters[:start_date] = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
      @filters[:end_date] = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
    else
      # Default to all time (no date filter)
      @filters[:start_date] = nil
      @filters[:end_date] = nil
    end
    
    # Bot filter
    case params[:bot_filter]
    when 'exclude_bots'
      @filters[:exclude_bots] = true
      @filters[:only_bots] = false
    when 'only_bots'
      @filters[:only_bots] = true
      @filters[:exclude_bots] = false
    when 'include_bots'
      @filters[:exclude_bots] = false
      @filters[:only_bots] = false
    else
      # DEFAULT: Exclude bots (show only real users)
      @filters[:exclude_bots] = true
      @filters[:only_bots] = false
    end
    
    # Account status
    case params[:account_status]
    when 'active'
      @filters[:exclude_deleted] = true
      @filters[:only_deleted] = false
    when 'deleted'
      @filters[:only_deleted] = true
      @filters[:exclude_deleted] = false
    when 'all'
      @filters[:exclude_deleted] = false
      @filters[:only_deleted] = false
    else
      # Default when no param sent: include all accounts (active and deleted)
      @filters[:exclude_deleted] = false
      @filters[:only_deleted] = false
    end
    
    # Gender
    @filters[:gender] = params[:gender] if params[:gender].present? && params[:gender] != 'all'
    
    # Device platform
    case params[:device_platform]
    when 'ios'
      @filters[:device_platform] = 0
    when 'android'
      @filters[:device_platform] = 1
    end
    
    # Subscription type
    @filters[:subscription_type] = params[:subscription_type] if params[:subscription_type].present? && params[:subscription_type] != 'all'
    
    # Location
    @filters[:country] = params[:country] if params[:country].present? && params[:country] != 'all'
    @filters[:city] = params[:city] if params[:city].present? && params[:city] != 'all'
    
    # Verification
    case params[:verified]
    when 'verified'
      @filters[:verified] = true
    when 'non_verified'
      @filters[:verified] = false
    end
    
    # Log parsed filters
    Rails.logger.debug "ANALYTICS FILTERS - Parsed @filters:"
    Rails.logger.debug @filters.inspect
    Rails.logger.debug "="*80
  end

  def growth_data
    {
      new_users_daily: AnalyticsService.new_users_over_time(@filters, :day),
      cumulative_users: AnalyticsService.cumulative_users(@filters),
      user_metrics: AnalyticsService.user_count_metrics(@filters),
      users_by_type: AnalyticsService.users_by_type(@filters),
      verified_distribution: AnalyticsService.verified_distribution(@filters),
      subscription_distribution: AnalyticsService.subscription_distribution(@filters),
      subscription_by_gender: AnalyticsService.subscription_by_gender(@filters),
      subscription_by_verified: AnalyticsService.subscription_by_verified(@filters),
      verified_by_gender: AnalyticsService.verified_by_gender(@filters),
      deletions: AnalyticsService.deletions_over_time(@filters)
    }
  end

  def demographics_data
    {
      gender_distribution: AnalyticsService.gender_distribution(@filters),
      age_distribution: AnalyticsService.age_distribution(@filters),
      top_countries: AnalyticsService.top_countries(@filters),
      top_cities: AnalyticsService.top_cities(@filters),
      avg_age_by_gender: AnalyticsService.average_age_by_gender(@filters)
    }
  end

  def insights_data
    {
      top_users: AnalyticsService.top_users(@filters),
      top_cities: AnalyticsService.top_performing_cities(@filters)
    }
  end

  def media_data
    {
      top_movies: AnalyticsService.top_movies(@filters, 20),
      top_series: AnalyticsService.top_series(@filters, 20),
      photos_distribution: AnalyticsService.photos_distribution(@filters)
    }
  end

  def interests_data
    {
      main_interests: AnalyticsService.main_interests_distribution(@filters),
      secondary_interests: AnalyticsService.secondary_interests_distribution(@filters),
      main_interests_count: AnalyticsService.main_interests_count_distribution(@filters),
      secondary_interests_count: AnalyticsService.secondary_interests_count_per_user(@filters)
    }
  end

  def spotify_data
    {
      artists_count_distribution: AnalyticsService.spotify_artists_count_distribution(@filters),
      top_artists: AnalyticsService.top_spotify_artists(@filters, 10)
    }
  end

  def languages_data
    {
      app_language_distribution: AnalyticsService.app_language_distribution(@filters),
      profile_languages_distribution: AnalyticsService.profile_languages_distribution(@filters),
      profile_languages_count_distribution: AnalyticsService.profile_languages_count_distribution(@filters)
    }
  end

  def invisible_mode_data
    {
      summary:    AnalyticsService.invisible_mode_summary(@filters),
      by_gender:  AnalyticsService.invisible_mode_by_gender(@filters)
    }
  end

  def blocks_data
    {
      totals:                AnalyticsService.blocks_total(@filters),
      over_time:             AnalyticsService.blocks_over_time(@filters),
      given_by_gender:       AnalyticsService.blocks_given_by_gender(@filters),
      received_by_gender:    AnalyticsService.blocks_received_by_gender(@filters),
      given_distribution:    AnalyticsService.blocks_given_distribution(@filters),
      received_distribution: AnalyticsService.blocks_received_distribution(@filters)
    }
  end

  def interactions_data
    {
      totals:                    AnalyticsService.interactions_totals(@filters),
      over_time:                 AnalyticsService.interactions_over_time(@filters),
      by_gender:                 AnalyticsService.interactions_by_gender(@filters),
      match_rate_by_gender:      AnalyticsService.match_rate_by_gender(@filters),
      likes_given_distribution:  AnalyticsService.likes_given_distribution(@filters),
      likes_received_distribution: AnalyticsService.likes_received_distribution(@filters)
    }
  end

  def complaints_data
    # ===== DIAGNOSTIC LOG =====
    filtered_user_ids = User.all.then { |s| AnalyticsService.send(:apply_filters, s, @filters) }.pluck(:id)
    raw_complaints    = AnalyticsService.send(:apply_user_filters_to_complaints, Complaint.all, @filters)
    complaint_rows    = raw_complaints.pluck(:id, :user_id, :to_user_id, :reason)

    Rails.logger.info "\n" + "="*100
    Rails.logger.info "[COMPLAINTS ANALYTICS] Diagnostic log"
    Rails.logger.info JSON.pretty_generate({
      filters_received: @filters,
      filtered_users: {
        count:  filtered_user_ids.size,
        ids:    filtered_user_ids
      },
      complaint_scope_sql: raw_complaints.to_sql,
      complaints_found: {
        count: complaint_rows.size,
        rows:  complaint_rows.map { |id, uid, tuid, reason|
          { id: id, reporter_id: uid, reported_id: tuid, reason: reason }
        }
      }
    })
    Rails.logger.info "="*100 + "\n"
    # ===== END DIAGNOSTIC LOG =====

    {
      total: AnalyticsService.complaints_total(@filters),
      over_time: AnalyticsService.complaints_over_time(@filters, :week),
      by_reporter_gender: AnalyticsService.complaints_by_reporter_gender(@filters),
      by_reported_gender: AnalyticsService.complaints_by_reported_gender(@filters),
      gender_matrix: AnalyticsService.complaints_gender_matrix(@filters),
      made_distribution: AnalyticsService.complaints_made_distribution(@filters),
      received_distribution: AnalyticsService.complaints_received_distribution(@filters),
      avg_received_by_gender: AnalyticsService.avg_complaints_received_by_gender(@filters),
      by_type_and_gender: AnalyticsService.complaints_by_type_and_gender(@filters)
    }
  end

  def check_admin
    unless current_user&.admin?
      redirect_to root_path, alert: "No tienes permisos para acceder a esta página"
    end
  end
  
  def table_exists?(table_name)
    ActiveRecord::Base.connection.table_exists?(table_name)
  end
end
