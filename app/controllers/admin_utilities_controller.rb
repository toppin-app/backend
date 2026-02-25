require 'ostruct'

class AdminUtilitiesController < ApplicationController
  before_action :check_admin

  def index
    @title = "Configuración y Utilidades"
    
    # Contar usuarios que necesitan población de ubicación
    @users_needing_location = User.where.not(lat: [nil, '']).where.not(lng: [nil, ''])
                                   .where("location_country IS NULL OR location_country = '' OR location_city IS NULL OR location_city = ''")
                                   .count
    
    # Contar usuarios que necesitan población de device_platform
    @users_needing_platform = User.where(device_platform: nil).where.not(device_id: [nil, '']).count
    
    # Estadísticas de device_platform
    @total_users = User.count
    @users_with_platform = User.where.not(device_platform: nil).count
    @ios_users = User.where(device_platform: 0).count
    @android_users = User.where(device_platform: 1).count
    
    # Obtener progreso actual si existe
    @current_progress = Rails.cache.read('location_population_progress')
    @platform_progress = Rails.cache.read('platform_population_progress')
  end

  def populate_locations
    require 'httparty'
    
    # Verificar si ya hay un proceso en ejecución
    if Rails.cache.read('location_population_running')
      render json: { error: 'Ya hay un proceso en ejecución' }, status: :conflict
      return
    end

    # Marcar proceso como en ejecución
    Rails.cache.write('location_population_running', true, expires_in: 2.hours)
    
    # Inicializar progreso
    progress = {
      status: 'running',
      total: 0,
      processed: 0,
      errors: 0,
      skipped: 0,
      current_user: nil,
      started_at: Time.current
    }
    Rails.cache.write('location_population_progress', progress)

    # Ejecutar en un thread para no bloquear la petición
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          # Buscar usuarios
          users = User.where.not(lat: [nil, '']).where.not(lng: [nil, ''])
                      .where("location_country IS NULL OR location_country = '' OR location_city IS NULL OR location_city = ''")
          
          total = users.count
          progress[:total] = total
          Rails.cache.write('location_population_progress', progress)
          
          processed = 0
          errors = 0
          skipped = 0
          
          users.find_each.with_index do |user, index|
            begin
              progress[:current_user] = { id: user.id, name: user.name, index: index + 1 }
              progress[:processed] = processed
              progress[:errors] = errors
              progress[:skipped] = skipped
              Rails.cache.write('location_population_progress', progress)
              
              # Hacer geocoding reverso con retry automático en caso de rate limit
              max_retries = 3
              attempt = 0
              success = false
              
              while attempt < max_retries && !success
                url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=#{user.lat}&lon=#{user.lng}"
                response = HTTParty.get(url, headers: { "User-Agent" => "ToppinApp/1.0" })
                
                if response.code == 429
                  # Rate limit - esperar más tiempo
                  Rails.logger.warn "⚠️ Rate limit en Nominatim (intento #{attempt + 1}/#{max_retries}), esperando 5 segundos..."
                  sleep 5
                  attempt += 1
                elsif response.success? && response['address']
                  address = response['address']
                  
                  city = address['city'] || address['town'] || address['village'] || address['hamlet'] || 
                         address['municipality'] || address['county']
                  country = address['country']
                  
                  if city.present? || country.present?
                    user.update_columns(
                      location_city: city || user.location_city,
                      location_country: country || user.location_country
                    )
                    processed += 1
                  else
                    skipped += 1
                  end
                  success = true
                else
                  errors += 1
                  success = true
                end
              end
              
              # Si llegamos al max de retries, contar como error
              if !success
                errors += 1
              end
              
              # Respetar límites de Nominatim (1 req/sec)
              sleep 1
              
            rescue => e
              errors += 1
              progress[:errors] = errors
              Rails.cache.write('location_population_progress', progress)
              Rails.logger.error "Error procesando usuario #{user.id}: #{e.message}"
            end
          end
          
          # Marcar como completado
          progress[:status] = 'completed'
          progress[:completed_at] = Time.current
          progress[:current_user] = nil
          progress[:processed] = processed
          progress[:errors] = errors
          progress[:skipped] = skipped
          Rails.cache.write('location_population_progress', progress)
          
        rescue => e
          progress[:status] = 'error'
          progress[:error_message] = e.message
          Rails.cache.write('location_population_progress', progress)
          Rails.logger.error "Error en populate_locations thread: #{e.message}\n#{e.backtrace.join("\n")}"
        ensure
          Rails.cache.delete('location_population_running')
        end
      end
    end

    render json: { message: 'Proceso iniciado', progress: progress }
  end

  def location_progress
    progress = Rails.cache.read('location_population_progress')
    render json: progress || { status: 'idle' }
  end

  def clear_location_progress
    Rails.cache.delete('location_population_progress')
    Rails.cache.delete('location_population_running')
    redirect_to admin_utilities_path, notice: 'Progreso limpiado'
  end

  def find_incomplete_users
    @title = "Configuración y Utilidades"
    
    # Contar usuarios que necesitan población de ubicación (para la otra utilidad)
    @users_needing_location = User.where.not(lat: [nil, '']).where.not(lng: [nil, ''])
                                   .where("location_country IS NULL OR location_country = '' OR location_city IS NULL OR location_city = ''")
                                   .count
    
    # Obtener progreso actual si existe
    @current_progress = Rails.cache.read('location_population_progress')
    
    field = params[:field_to_validate]
    
    if field.present?
      @incomplete_users = case field
      when 'image'
        @field_label = "imagen de perfil"
        user_ids_without_media = User.active_accounts.left_joins(:user_media)
                                     .group('users.id')
                                     .having('COUNT(user_media.id) = 0')
                                     .pluck(:id)
        User.active_accounts.includes(:user_media).where(id: user_ids_without_media)
      when 'name'
        @field_label = "nombre"
        User.active_accounts.includes(:user_media).where("name IS NULL OR TRIM(name) = ''")
      when 'email'
        @field_label = "email"
        User.active_accounts.includes(:user_media).where("email IS NULL OR TRIM(email) = ''")
      when 'gender'
        @field_label = "género"
        User.active_accounts.includes(:user_media).where(gender: nil)
      when 'birthday'
        @field_label = "fecha de nacimiento"
        User.active_accounts.includes(:user_media).where(birthday: nil)
      when 'description'
        @field_label = "descripción"
        User.active_accounts.includes(:user_media).where("description IS NULL OR TRIM(description) = ''")
      when 'location_country'
        @field_label = "país"
        User.active_accounts.includes(:user_media).where("location_country IS NULL OR TRIM(location_country) = ''")
      when 'location_city'
        @field_label = "ciudad"
        User.active_accounts.includes(:user_media).where("location_city IS NULL OR TRIM(location_city) = ''")
      when 'coordinates'
        @field_label = "coordenadas"
        User.active_accounts.includes(:user_media).where("lat IS NULL OR TRIM(CAST(lat AS CHAR)) = '' OR lng IS NULL OR TRIM(CAST(lng AS CHAR)) = ''")
      when 'occupation'
        @field_label = "ocupación"
        User.active_accounts.includes(:user_media).where("occupation IS NULL OR TRIM(occupation) = ''")
      when 'studies'
        @field_label = "estudios"
        User.active_accounts.includes(:user_media).where("studies IS NULL OR TRIM(studies) = ''")
      else
        @field_label = "datos"
        User.none
      end
    end
    
    render :index
  end

  def bulk_delete_users
    user_ids = params[:user_ids] || []
    
    if user_ids.any?
      deleted_count = 0
      user_ids.each do |user_id|
        user = User.find_by(id: user_id)
        if user
          begin
            user.destroy
            deleted_count += 1
          rescue ActiveRecord::StatementInvalid => e
            # Manejar errores de tablas faltantes
            if e.message.include?("doesn't exist")
              # Eliminar manualmente las dependencias
              user.user_match_requests.delete_all rescue nil
              user.user_interests.delete_all rescue nil
              user.user_main_interests.delete_all rescue nil
              user.user_media.delete_all rescue nil
              user.devices.delete_all rescue nil
              user.user_filter_preference&.delete rescue nil
              user.user_info_item_values.delete_all rescue nil
              user.user_publis.delete_all rescue nil
              user.banner_users.delete_all rescue nil
              user.user_vip_unlocks.delete_all rescue nil
              user.spotify_user_data.delete_all rescue nil
              user.tmdb_user_data.delete_all rescue nil
              user.tmdb_user_series_data.delete_all rescue nil
              user.complaints.delete_all rescue nil
              user.received_complaints.delete_all rescue nil
              user.blocks.delete_all rescue nil
              user.delete
              deleted_count += 1
            else
              raise e
            end
          end
        end
      end
      
      respond_to do |format|
        format.html { redirect_to admin_utilities_path, notice: "#{deleted_count} usuarios eliminados correctamente" }
        format.js do
          render js: "
            #{user_ids.map { |id| "document.getElementById('user-card-#{id}')?.remove();" }.join("\n")}
            updateTotalCount();
            hideLoading();
            alert('#{deleted_count} usuarios eliminados correctamente');
          "
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_utilities_path, alert: 'No se seleccionaron usuarios para eliminar' }
        format.js { render js: "hideLoading(); alert('No se seleccionaron usuarios para eliminar');" }
      end
    end
  end

  def populate_device_platforms
    # Verificar si ya hay un proceso en ejecución
    if Rails.cache.read('platform_population_running')
      render json: { error: 'Ya hay un proceso en ejecución' }, status: :conflict
      return
    end

    # Marcar proceso como en ejecución
    Rails.cache.write('platform_population_running', true, expires_in: 30.minutes)
    
    begin
      # Patrones de detección
      ios_pattern = /^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$/i
      android_pattern = /^[a-f0-9]{16}$/i
      
      # Buscar usuarios sin device_platform pero con device_id
      users = User.where(device_platform: nil).where.not(device_id: [nil, ''])
      
      total = users.count
      processed = 0
      ios_detected = 0
      android_detected = 0
      skipped = 0
      
      Rails.logger.info "🚀 Iniciando detección síncrona de #{total} usuarios"
      
      users.find_each do |user|
        device_id_clean = user.device_id.to_s.strip
        
        if device_id_clean.match?(ios_pattern)
          user.update_column(:device_platform, 0) # iOS
          processed += 1
          ios_detected += 1
        elsif device_id_clean.match?(android_pattern)
          user.update_column(:device_platform, 1) # Android
          processed += 1
          android_detected += 1
        else
          skipped += 1
        end
      rescue => e
        skipped += 1
        Rails.logger.error "Error procesando usuario #{user.id}: #{e.message}"
      end
      
      result = {
        status: 'completed',
        total: total,
        processed: processed,
        ios_detected: ios_detected,
        android_detected: android_detected,
        skipped: skipped
      }
      
      Rails.logger.info "✅ Proceso completado: #{result.inspect}"
      
      render json: { message: 'Proceso completado', result: result }
      
    rescue => e
      Rails.logger.error "❌ Error en populate_device_platforms: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: :internal_server_error
    ensure
      Rails.cache.delete('platform_population_running')
    end
  end

  def platform_progress
    progress = Rails.cache.read('platform_population_progress')
    Rails.logger.info "📊 Progress request - Cache contenido: #{progress.inspect}"
    render json: progress || { status: 'idle' }
  end

  def clear_platform_progress
    Rails.cache.delete('platform_population_progress')
    Rails.cache.delete('platform_population_running')
    redirect_to admin_utilities_path, notice: 'Progreso de plataforma limpiado'
  end

  def validate_tmdb
    @title = "Configuración y Utilidades"
    content_type = params[:content_type] || 'movies'
    
    if content_type == 'movies'
      @content_type_label = 'películas'
      validate_movies
    else
      @content_type_label = 'series'
      validate_series
    end
    
    render :index
  end

  private

  def validate_movies
    # Obtener todas las películas agrupadas por tmdb_id con conteo de usuarios
    movies_data = TmdbUserDatum.select('tmdb_id, MAX(title) as title, MAX(poster_path) as poster_path, COUNT(DISTINCT user_id) as user_count, GROUP_CONCAT(DISTINCT user_id) as user_ids')
                                .group(:tmdb_id)
                                .having('tmdb_id IS NOT NULL')
    
    @tmdb_problems = []
    
    movies_data.each do |movie|
      issues = []
      
      # Validar título
      if movie.title.blank? || movie.title == 'undefined' || movie.title == 'null'
        issues << "Título vacío, undefined o null"
      end
      
      # Validar poster_path
      if movie.poster_path.blank? || movie.poster_path == 'undefined' || movie.poster_path == 'null'
        issues << "Poster path vacío, undefined o null"
      end
      
      # Validar tmdb_id
      if movie.tmdb_id.blank? || movie.tmdb_id.to_s == 'undefined' || movie.tmdb_id.to_s == 'null'
        issues << "TMDB ID vacío, undefined o null"
      end
      
      # Si hay problemas, agregarlo a la lista
      if issues.any?
        affected_user_ids = movie.user_ids.to_s.split(',').map(&:to_i)
        
        @tmdb_problems << OpenStruct.new(
          tmdb_id: movie.tmdb_id,
          title: movie.title,
          name: nil,
          poster_path: movie.poster_path,
          user_count: movie.user_count,
          affected_user_ids: affected_user_ids,
          issues: issues
        )
      end
    end
    
    # Ordenar por número de usuarios afectados (descendente)
    @tmdb_problems.sort_by! { |p| -p.user_count }
  end

  def validate_series
    # Obtener todas las series agrupadas por tmdb_id con conteo de usuarios
    series_data = TmdbUserSeriesDatum.select('tmdb_id, MAX(name) as name, MAX(poster_path) as poster_path, COUNT(DISTINCT user_id) as user_count, GROUP_CONCAT(DISTINCT user_id) as user_ids')
                                      .group(:tmdb_id)
                                      .having('tmdb_id IS NOT NULL')
    
    @tmdb_problems = []
    
    series_data.each do |series|
      issues = []
      
      # Validar nombre
      if series.name.blank? || series.name == 'undefined' || series.name == 'null'
        issues << "Nombre vacío, undefined o null"
      end
      
      # Validar poster_path
      if series.poster_path.blank? || series.poster_path == 'undefined' || series.poster_path == 'null'
        issues << "Poster path vacío, undefined o null"
      end
      
      # Validar tmdb_id
      if series.tmdb_id.blank? || series.tmdb_id.to_s == 'undefined' || series.tmdb_id.to_s == 'null'
        issues << "TMDB ID vacío, undefined o null"
      end
      
      # Si hay problemas, agregarlo a la lista
      if issues.any?
        affected_user_ids = series.user_ids.to_s.split(',').map(&:to_i)
        
        @tmdb_problems << OpenStruct.new(
          tmdb_id: series.tmdb_id,
          title: nil,
          name: series.name,
          poster_path: series.poster_path,
          user_count: series.user_count,
          affected_user_ids: affected_user_ids,
          issues: issues
        )
      end
    end
    
    # Ordenar por número de usuarios afectados (descendente)
    @tmdb_problems.sort_by! { |p| -p.user_count }
  end

  def check_admin
    unless current_user&.admin?
      redirect_to root_path, alert: 'Acceso denegado'
    end
  end
end
