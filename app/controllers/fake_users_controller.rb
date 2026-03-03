class FakeUsersController < ApplicationController
  before_action :check_admin

  # GET /fake_users
  def index
    @title = "Gestión de Usuarios Fake (BOT)"

    # Asegurarse de que params[:q] sea un hash
    if params[:q].is_a?(String)
      params[:q] = nil
    end

    if !params[:q].nil? && params[:q].is_a?(Hash)
      @search = params[:q][:email_or_name_cont]
    else
      @search = ""
    end

    # Base: solo usuarios fake y activos (no eliminados)
    base_users = User.fake_users.active_accounts
    
    # Filtrar por usuarios bloqueados si se especifica
    if params[:show_blocked_users] == '1'
      base_users = base_users.where(blocked: true)
    end
    
    @q = base_users.ransack(params[:q])
    
    # Manejar usuarios por página: personalizado o predefinido
    if params[:per_page] == 'custom' && params[:custom_per_page].present?
      per_page = [params[:custom_per_page].to_i, 500].min # Máximo 500
      per_page = [per_page, 1].max # Mínimo 1
    else
      per_page = params[:per_page].present? ? params[:per_page].to_i : 20
    end
    
    # Aplicar ordenamiento: si hay un sort de Ransack, usarlo; si no, ordenar por ID descendente
    sorted_users = @q.result
    if params[:q].present? && params[:q][:s].present?
      # Ransack maneja el ordenamiento
      @users = sorted_users.paginate(:page => params[:page], :per_page => per_page)
    else
      # Ordenamiento por defecto
      @users = sorted_users.order("id DESC").paginate(:page => params[:page], :per_page => per_page)
    end
    
    @show_blocked_users = params[:show_blocked_users] == '1'
    
    # Obtener lista única de países y ciudades para los filtros
    @countries = User.fake_users.active_accounts.where.not(location_country: [nil, '']).distinct.pluck(:location_country).sort
    @cities = User.fake_users.active_accounts.where.not(location_city: [nil, '']).distinct.pluck(:location_city).sort
  end

  # POST /fake_users/bulk_update_location
  def bulk_update_location
    user_ids = params[:user_ids] || []
    
    if user_ids.empty?
      redirect_to fake_users_path, alert: 'No se seleccionaron usuarios'
      return
    end

    # Verificar que todos los usuarios sean fake
    users = User.fake_users.where(id: user_ids)
    
    if users.count != user_ids.count
      redirect_to fake_users_path, alert: 'Algunos usuarios seleccionados no son usuarios fake'
      return
    end

    # Actualizar ubicación
    location_params = {
      lat: params[:lat],
      lng: params[:lng],
      location_city: params[:location_city],
      location_country: params[:location_country]
    }

    updated_count = 0
    users.each do |user|
      if user.update(location_params)
        updated_count += 1
      end
    end

    redirect_to fake_users_path, notice: "Se actualizó la ubicación de #{updated_count} usuario(s) fake"
  end
end
