class AnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :check_admin
  before_action :parse_filters, only: [:index, :data]

  def index
    @title = "User Analytics Dashboard"
    
    # Pre-load key metrics for initial page load
    @key_metrics = {
      total_users: User.where(deleted_account: false, fake_user: false).count,
      total_matches: UserMatchRequest.where(is_match: true).count,
      total_revenue: table_exists?('purchases') ? Purchase.sum(:price) : 0,
      active_users_today: User.where('last_sign_in_at >= ?', 24.hours.ago).where(deleted_account: false).count
    }
    
    # Filter options
    @countries = User.where.not(location_country: nil).distinct.pluck(:location_country).sort
    @cities = User.where.not(location_city: nil).distinct.pluck(:location_city).sort
  end

  def data
    section = params[:section]
    
    data = case section
    when 'growth'
      growth_data
    when 'engagement'
      engagement_data
    when 'demographics'
      demographics_data
    when 'matching'
      matching_data
    when 'monetization'
      monetization_data
    when 'retention'
      retention_data
    when 'insights'
      insights_data
    else
      { error: 'Invalid section' }
    end
    
    render json: data
  end

  private

  def parse_filters
    @filters = {}
    
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
      # Default: exclude bots (fake_user: false) for cleaner data
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
      # Default: active accounts only (exclude deleted)
      @filters[:exclude_deleted] = true
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
  end

  def growth_data
    {
      new_users_daily: AnalyticsService.new_users_over_time(@filters, :day),
      cumulative_users: AnalyticsService.cumulative_users(@filters),
      user_metrics: AnalyticsService.user_count_metrics(@filters),
      users_by_type: AnalyticsService.users_by_type(@filters),
      verified_distribution: AnalyticsService.verified_distribution(@filters),
      deletions: AnalyticsService.deletions_over_time(@filters)
    }
  end

  def engagement_data
    {
      dau: AnalyticsService.daily_active_users(@filters),
      engagement_metrics: AnalyticsService.engagement_metrics(@filters),
      likes_sent: AnalyticsService.likes_sent_over_time(@filters),
      matches_created: AnalyticsService.matches_created_over_time(@filters),
      average_engagement: AnalyticsService.average_engagement(@filters)
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

  def matching_data
    {
      match_metrics: AnalyticsService.match_metrics(@filters),
      matches_distribution: AnalyticsService.matches_distribution(@filters)
    }
  end

  def monetization_data
    {
      subscription_distribution: AnalyticsService.subscription_distribution(@filters),
      revenue_over_time: AnalyticsService.revenue_over_time(@filters),
      revenue_metrics: AnalyticsService.revenue_metrics(@filters),
      platform_revenue: AnalyticsService.platform_revenue(@filters),
      boost_superlike: AnalyticsService.boost_superlike_usage(@filters)
    }
  end

  def retention_data
    {
      cohorts: AnalyticsService.retention_cohorts(@filters),
      churn: AnalyticsService.churn_metrics(@filters)
    }
  end

  def insights_data
    {
      top_users: AnalyticsService.top_users(@filters),
      top_cities: AnalyticsService.top_performing_cities(@filters)
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
