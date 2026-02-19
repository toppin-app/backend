class PublisController < ApplicationController
  before_action :set_publi, only: %i[ show edit update destroy ]

  # GET /publis or /publis.json
  def index
    @publis = Publi.all.order(id: :desc)
    @title = "Publicidad"
  end

  # GET /publis/1 or /publis/1.json
  def show
    @title = "Información del anuncio"
    
    # Determinar modo de visualización (viewed o opened)
    @analytics_mode = params[:mode] || 'viewed'
    unless ['viewed', 'opened'].include?(@analytics_mode)
      @analytics_mode = 'viewed'
    end
    
    # Construir el filtro dinámico basado en el modo
    if @analytics_mode == 'viewed'
      @filter_condition = { viewed: true }
    else # opened
      @filter_condition = "opened_at IS NOT NULL"
    end
    
    # Métricas de desempeño
    @total_impressions = @publi.user_publis.where(@filter_condition).count
    @unique_viewers = @publi.user_publis.where(@filter_condition).select(:user_id).distinct.count
    
    # Datos agrupados por plataforma (iOS, Android)
    @impressions_by_platform = @publi.user_publis
      .where(@filter_condition)
      .joins(:user)
      .group("users.device_platform")
      .count
    
    # Debug: Log de los valores reales de plataforma
    Rails.logger.info "Platform data: #{@impressions_by_platform.inspect}"
    
    # Determinar qué campo de fecha usar según el modo
    date_field = @analytics_mode == 'viewed' ? 'users_publis.created_at' : 'users_publis.opened_at'
    
    # Obtener datos consolidados por día (todo el historial de la campaña)
    # Una sola query que devuelve ambas métricas por fecha
    temporal_data = @publi.user_publis
      .where(@filter_condition)
      .group("DATE(#{date_field})")
      .select("DATE(#{date_field}) as date, 
               COUNT(*) as total_impressions,
               COUNT(DISTINCT user_id) as unique_users")
      .order("date")
    
    # Construir array consolidado para el frontend
    @temporal_chart_data = temporal_data.map do |row|
      {
        date: row.date.to_s,
        impressions: row.total_impressions,
        unique_users: row.unique_users
      }
    end
    
    # Usuarios que han visto la publicidad (para análisis de tipo de usuario)
    # Gender es un enum: female: 0, male: 1, non_binary: 2, couple: 3
    gender_counts = @publi.user_publis
      .where(@filter_condition)
      .joins(:user)
      .group("users.gender")
      .count
    
    # Convertir las claves numéricas a nombres de enum
    gender_map = { 0 => 'female', 1 => 'male', 2 => 'non_binary', 3 => 'couple' }
    @viewer_genders = gender_counts.transform_keys { |k| gender_map[k] || k.to_s }.compact
    
    # Debug: Log de los valores reales de género
    Rails.logger.info "Gender data: #{@viewer_genders.inspect}"
    
    # Distribución por rango de edad (calculada desde birthday)
    @age_distribution = @publi.user_publis
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
    
    # Top intereses principales (user_main_interests) - máximo 4 por usuario
    filter_sql = @analytics_mode == 'viewed' ? 
      "users_publis.publi_id = ? AND users_publis.viewed = ?" : 
      "users_publis.publi_id = ? AND users_publis.opened_at IS NOT NULL"
    filter_params = [@publi.id]
    filter_params << true if @analytics_mode == 'viewed'
    # Top intereses principales (user_main_interests) - máximo 4 por usuario
    filter_sql = @analytics_mode == 'viewed' ? 
      "users_publis.publi_id = ? AND users_publis.viewed = ?" : 
      "users_publis.publi_id = ? AND users_publis.opened_at IS NOT NULL"
    filter_params = [@publi.id]
    filter_params << true if @analytics_mode == 'viewed'
    
    @top_main_interests = Interest
      .joins("INNER JOIN user_main_interests ON interests.id = user_main_interests.interest_id")
      .joins("INNER JOIN users ON user_main_interests.user_id = users.id")
      .joins("INNER JOIN users_publis ON users.id = users_publis.user_id")
      .where(filter_sql, *filter_params)
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
      .joins("INNER JOIN users_publis ON users.id = users_publis.user_id")
      .where(filter_sql, *filter_params)
      .group("interests.id", "interests.name")
      .select("interests.name, COUNT(DISTINCT user_interests.id) as interest_count")
      .order("interest_count DESC")
      .limit(10)
      .map { |i| [i.name, i.interest_count] }
      .to_h
    
    # Distribución por geolocalización (ciudad y país) - desde users_publis
    @location_distribution = @publi.user_publis
      .where(@filter_condition)
      .where.not(locality: nil)
      .group(:locality, :country)
      .select("locality, country, COUNT(*) as count")
      .order("count DESC")
      .limit(10)
      .map { |l| ["#{l.locality}, #{l.country}", l.count] }
      .to_h
    
    # Distribución por día de la semana
    @weekday_distribution = @publi.user_publis
      .where(@filter_condition)
      .select("DAYOFWEEK(COALESCE(users_publis.created_at, users_publis.updated_at)) as day_of_week, COUNT(*) as count")
      .group("day_of_week")
      .order("day_of_week")
      .map { |d| [d.day_of_week, d.count] }
      .to_h
    
    # Log de debugging adicional
    Rails.logger.info "Analytics mode: #{@analytics_mode}"
    Rails.logger.info "Date field used: #{@analytics_mode == 'viewed' ? 'created_at' : 'opened_at'}"
    Rails.logger.info "Temporal chart data: #{@temporal_chart_data.inspect}"
    Rails.logger.info "Age distribution: #{@age_distribution.inspect}"
    Rails.logger.info "Location distribution: #{@location_distribution.inspect}"
    Rails.logger.info "Weekday distribution: #{@weekday_distribution.inspect}"
    Rails.logger.info "Top main interests: #{@top_main_interests.inspect}"
    Rails.logger.info "Top secondary interests: #{@top_secondary_interests.inspect}"
    
    # Conversión aproximada (usuarios que hicieron clic - si tenemos el link)
    @has_link = @publi.link.present?
  end

  # GET /publis/new
  def new
    @publi = Publi.new
    @title = "Nuevo anuncio"
    set_weekdays
  end

  # GET /publis/1/edit
  def edit
      @title = "Editar anuncio"
      @edit = true
  end

  # POST /publis or /publis.json
  def create
    @publi = Publi.new(publi_params)
    process_weekdays
    respond_to do |format|
      if @publi.save
        format.html { redirect_to @publi, notice: "Anuncio creado con éxito." }
        format.json { render :show, status: :created, location: @publi }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @publi.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /publis/1 or /publis/1.json
  def update
    process_weekdays
    respond_to do |format|
      if @publi.update(publi_params)
        format.html { redirect_to @publi, notice: "Anuncio editado con éxito." }
        format.json { render :show, status: :ok, location: @publi }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @publi.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /publis/1 or /publis/1.json
  def destroy
    @publi.destroy
    respond_to do |format|
      format.html { redirect_to publis_url, notice: "Anuncio eliminado con éxito." }
      format.json { head :no_content }
    end
  end

  def process_weekdays
     weekdays = ""
     params[:publi][:weekdays].each do |weekday|
          if weekday.present?
              weekdays = weekdays+weekday+","
          end
      end
      weekdays = weekdays.chop
      @publi.weekdays = weekdays
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_publi
      @publi = Publi.find(params[:id])
      set_weekdays
    end

    def set_weekdays
      @weekdays = [["Lunes", 1], ["Martes", 2], ["Miércoles", 3], ["Jueves", 4], ["Viernes", 5], ["Sábado", 6], ["Domingo", 7]]
    end

    # Only allow a list of trusted parameters through.
    def publi_params
      params.require(:publi).permit(:title, :start_date, :end_date, :weekdays, :start_time, :end_time, :image, :video, :link, :cancellable, :repeat_swipes)
    end
end
