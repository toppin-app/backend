class AdminUtilitiesController < ApplicationController
  before_action :check_admin

  def index
    @title = "Configuración y Utilidades"
    
    # Contar usuarios que necesitan población de ubicación
    @users_needing_location = User.where.not(lat: [nil, '']).where.not(lng: [nil, ''])
                                   .where("location_country IS NULL OR location_country = '' OR location_city IS NULL OR location_city = ''")
                                   .count
    
    # Obtener progreso actual si existe
    @current_progress = Rails.cache.read('location_population_progress')
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
            Rails.cache.write('location_population_progress', progress)
            
            # Hacer geocoding reverso
            url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=#{user.lat}&lon=#{user.lng}"
            response = HTTParty.get(url, headers: { "User-Agent" => "ToppinApp/1.0" })
            
            if response.success? && response['address']
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
            else
              errors += 1
            end
            
            # Actualizar progreso
            progress[:processed] = processed
            progress[:errors] = errors
            progress[:skipped] = skipped
            Rails.cache.write('location_population_progress', progress)
            
            # Respetar límites de Nominatim
            sleep 1
            
          rescue => e
            errors += 1
            progress[:errors] = errors
            Rails.cache.write('location_population_progress', progress)
          end
        end
        
        # Marcar como completado
        progress[:status] = 'completed'
        progress[:completed_at] = Time.current
        progress[:current_user] = nil
        Rails.cache.write('location_population_progress', progress)
        
      rescue => e
        progress[:status] = 'error'
        progress[:error_message] = e.message
        Rails.cache.write('location_population_progress', progress)
      ensure
        Rails.cache.delete('location_population_running')
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

  private

  def check_admin
    unless current_user&.admin?
      redirect_to root_path, alert: 'Acceso denegado'
    end
  end
end
