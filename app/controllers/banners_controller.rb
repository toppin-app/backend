class BannersController < ApplicationController
  before_action :set_banner, only: %i[show edit update destroy]
  before_action :check_admin

  # GET /banners
  def index
    @banners = Banner.all.order(created_at: :desc)
  end

  # GET /banners/1
  def show
    @title = "Información del banner"
    
    # Determinar modo de visualización (viewed o opened)
    @analytics_mode = params[:mode] || 'viewed'
    unless ['viewed', 'opened'].include?(@analytics_mode)
      @analytics_mode = 'viewed'
    end
    
    # Construir el filtro dinámico basado en el modo
    if @analytics_mode == 'viewed'
      @filter_condition = "viewed_at IS NOT NULL"
    else # opened
      @filter_condition = "opened_at IS NOT NULL"
    end
    
    # Métricas de desempeño
    @total_impressions = @banner.banner_users.where(@filter_condition).count
    @unique_viewers = @banner.banner_users.where(@filter_condition).select(:user_id).distinct.count
    
    # Datos agrupados por plataforma (JOIN con users)
    @impressions_by_platform = @banner.banner_users
      .where(@filter_condition)
      .joins(:user)
      .group("users.device_platform")
      .count
    
    # Determinar qué campo de fecha usar según el modo
    date_field = @analytics_mode == 'viewed' ? 'banner_users.viewed_at' : 'banner_users.opened_at'
    
    # Datos temporales con usuarios únicos acumulativos
    temporal_data = @banner.banner_users
      .where(@filter_condition)
      .group("DATE(#{date_field})")
      .select("DATE(#{date_field}) as date, COUNT(*) as total_impressions")
      .order("date")
    
    @temporal_chart_data = temporal_data.map do |row|
      users_up_to_date = @banner.banner_users
        .where(@filter_condition)
        .where("DATE(#{date_field}) <= ?", row.date)
        .select(:user_id)
        .distinct
        .count
      
      {
        date: row.date.to_s,
        impressions: row.total_impressions,
        unique_users: users_up_to_date
      }
    end
    
    # Usuarios por género (JOIN con users)
    gender_counts = @banner.banner_users
      .where(@filter_condition)
      .joins(:user)
      .group("users.gender")
      .count
    
    gender_map = { 0 => 'female', 1 => 'male', 2 => 'non_binary', 3 => 'couple' }
    @viewer_genders = gender_counts.transform_keys { |k| gender_map[k] || k.to_s }.compact
    
    # Distribución por edad (JOIN con users)
    @age_distribution = @banner.banner_users
      .where(@filter_condition)
      .joins(:user)
      .where.not("users.birthday" => nil)
      .select("CASE
        WHEN TIMESTAMPDIFF(YEAR, users.birthday, CURDATE()) < 18 THEN '< 18'
        WHEN TIMESTAMPDIFF(YEAR, users.birthday, CURDATE()) BETWEEN 18 AND 24 THEN '18-24'
        WHEN TIMESTAMPDIFF(YEAR, users.birthday, CURDATE()) BETWEEN 25 AND 34 THEN '25-34'
        WHEN TIMESTAMPDIFF(YEAR, users.birthday, CURDATE()) BETWEEN 35 AND 44 THEN '35-44'
        WHEN TIMESTAMPDIFF(YEAR, users.birthday, CURDATE()) BETWEEN 45 AND 54 THEN '45-54'
        ELSE '55+'
      END as age_range, COUNT(DISTINCT users.id) as count")
      .group("age_range")
      .order("age_range")
      .map { |r| [r.age_range, r.count] }
      .to_h
    
    # Top intereses principales (user_main_interests)
    filter_sql = @analytics_mode == 'viewed' ? 
      "banner_users.banner_id = ? AND banner_users.viewed_at IS NOT NULL" : 
      "banner_users.banner_id = ? AND banner_users.opened_at IS NOT NULL"
    
    @top_main_interests = Interest
      .joins("INNER JOIN user_main_interests ON interests.id = user_main_interests.interest_id")
      .joins("INNER JOIN users ON user_main_interests.user_id = users.id")
      .joins("INNER JOIN banner_users ON users.id = banner_users.user_id")
      .where(filter_sql, @banner.id)
      .group("interests.id", "interests.name")
      .select("interests.name, COUNT(DISTINCT user_main_interests.id) as interest_count")
      .order("interest_count DESC")
      .limit(10)
      .map { |i| [i.name, i.interest_count] }
      .to_h
    
    # Top intereses secundarios (user_interests)
    @top_secondary_interests = Interest
      .joins("INNER JOIN user_interests ON interests.id = user_interests.interest_id")
      .joins("INNER JOIN users ON user_interests.user_id = users.id")
      .joins("INNER JOIN banner_users ON users.id = banner_users.user_id")
      .where(filter_sql, @banner.id)
      .group("interests.id", "interests.name")
      .select("interests.name, COUNT(DISTINCT user_interests.id) as interest_count")
      .order("interest_count DESC")
      .limit(10)
      .map { |i| [i.name, i.interest_count] }
      .to_h
    
    # Distribución por geolocalización (datos de banner_users, no JOIN)
    @location_distribution = @banner.banner_users
      .where(@filter_condition)
      .where.not(locality: nil)
      .group("banner_users.locality", "banner_users.country")
      .select("banner_users.locality as locality, banner_users.country as country, COUNT(*) as count")
      .order("count DESC")
      .limit(10)
      .map { |l| ["#{l.locality}, #{l.country}", l.count] }
      .to_h
    
    # Día de la semana
    @weekday_distribution = @banner.banner_users
      .where(@filter_condition)
      .select("DAYOFWEEK(#{date_field}) as day_of_week, COUNT(*) as count")
      .group("day_of_week")
      .order("day_of_week")
      .map { |d| [d.day_of_week, d.count] }
      .to_h
    
    # Tiene link?
    @has_link = @banner.url.present?
  end

  # GET /banners/new
  def new
    @banner = Banner.new
  end

  # GET /banners/1/edit
  def edit
  end

  # POST /banners
  def create
    @banner = Banner.new(banner_params)

    respond_to do |format|
      if @banner.save
        format.html { redirect_to @banner, notice: 'Banner creado exitosamente.' }
        format.json { render :show, status: :created, location: @banner }
      else
        format.html { render :new }
        format.json { render json: @banner.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /banners/1
  def update
    respond_to do |format|
      if @banner.update(banner_params)
        format.html { redirect_to @banner, notice: 'Banner actualizado exitosamente.' }
        format.json { render :show, status: :ok, location: @banner }
      else
        format.html { render :edit }
        format.json { render json: @banner.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /banners/1
  def destroy
    @banner.destroy
    respond_to do |format|
      format.html { redirect_to banners_url, notice: 'Banner eliminado exitosamente.' }
      format.json { head :no_content }
    end
  end

  private

  def set_banner
    @banner = Banner.find(params[:id])
  end

  def banner_params
    params.require(:banner).permit(:title, :description, :image, :url, :active, :start_date, :end_date)
  end
end