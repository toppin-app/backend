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
    
    # Métricas de desempeño
    @total_impressions = @publi.user_publis.where(viewed: true).count
    @unique_viewers = @publi.viewers.distinct.count
    
    # Datos agrupados por plataforma (iOS, Android)
    @impressions_by_platform = @publi.user_publis
      .where(viewed: true)
      .joins(:user)
      .group("users.device_platform")
      .count
    
    # Debug: Log de los valores reales de plataforma
    Rails.logger.info "Platform data: #{@impressions_by_platform.inspect}"
    
    # Impresiones por día (últimos 30 días)
    @impressions_by_day = @publi.user_publis
      .where(viewed: true)
      .where("users_publis.created_at >= ?", 30.days.ago)
      .group("DATE(users_publis.created_at)")
      .count
      .sort_by { |date, _| date }
    
    # Usuarios únicos por día (últimos 30 días) - para la nueva gráfica
    @unique_users_by_day = @publi.user_publis
      .where(viewed: true)
      .where("users_publis.created_at >= ?", 30.days.ago)
      .group("DATE(users_publis.created_at)")
      .select("DATE(users_publis.created_at) as date, COUNT(DISTINCT user_id) as unique_count")
      .group("date")
      .order("date")
      .map { |r| [r.date.to_s, r.unique_count] }
      .to_h
    
    # Usuarios que han visto la publicidad (para análisis de tipo de usuario)
    # Gender es un enum: female: 0, male: 1, non_binary: 2, couple: 3
    @viewer_genders = @publi.viewers.group(:gender).count
    
    # Debug: Log de los valores reales de género
    Rails.logger.info "Gender data: #{@viewer_genders.inspect}"
    
    # Distribución por rango de edad (calculada desde birthday)
    @age_distribution = @publi.viewers
      .where.not(birthday: nil)
      .select("CASE
        WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 18 THEN '< 18'
        WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) BETWEEN 18 AND 24 THEN '18-24'
        WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) BETWEEN 25 AND 34 THEN '25-34'
        WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) BETWEEN 35 AND 44 THEN '35-44'
        WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) BETWEEN 45 AND 54 THEN '45-54'
        ELSE '55+'
      END as age_range, COUNT(*) as count")
      .group("age_range")
      .order("age_range")
      .map { |r| [r.age_range, r.count] }
      .to_h
    
    # Top intereses de los espectadores (a través de user_interests)
    @top_interests = Interest
      .joins(user_interests: :user)
      .joins("INNER JOIN users_publis ON users.id = users_publis.user_id")
      .where("users_publis.publi_id = ? AND users_publis.viewed = ?", @publi.id, true)
      .group("interests.id", "interests.name")
      .select("interests.name, COUNT(DISTINCT users.id) as user_count")
      .order("user_count DESC")
      .limit(10)
      .map { |i| [i.name, i.user_count] }
      .to_h
    
    # Distribución por geolocalización (ciudad y país) - desde users_publis
    @location_distribution = @publi.user_publis
      .where(viewed: true)
      .where.not(locality: nil)
      .group(:locality, :country)
      .select("locality, country, COUNT(*) as count")
      .order("count DESC")
      .limit(10)
      .map { |l| ["#{l.locality}, #{l.country}", l.count] }
      .to_h
    
    # Distribución por horario de visualización (horas del día)
    @hourly_distribution = @publi.user_publis
      .where(viewed: true)
      .select("HOUR(COALESCE(users_publis.created_at, users_publis.updated_at)) as hour, COUNT(*) as count")
      .group("hour")
      .order("hour")
      .map { |h| [h.hour, h.count] }
      .to_h
    
    # Distribución por día de la semana
    @weekday_distribution = @publi.user_publis
      .where(viewed: true)
      .select("DAYOFWEEK(COALESCE(users_publis.created_at, users_publis.updated_at)) as day_of_week, COUNT(*) as count")
      .group("day_of_week")
      .order("day_of_week")
      .map { |d| [d.day_of_week, d.count] }
      .to_h
    
    # Log de debugging adicional
    Rails.logger.info "Age distribution: #{@age_distribution.inspect}"
    Rails.logger.info "Location distribution: #{@location_distribution.inspect}"
    Rails.logger.info "Hourly distribution: #{@hourly_distribution.inspect}"
    Rails.logger.info "Weekday distribution: #{@weekday_distribution.inspect}"
    Rails.logger.info "Top interests: #{@top_interests.inspect}"
    
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
