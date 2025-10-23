class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :destroy, :block]
  before_action :check_admin, only: [:index, :new, :edit, :create_match, :create_like, :unmatch]
  skip_before_action :verify_authenticity_token, :only => [:show, :edit, :update, :destroy, :block]
  skip_before_action :authenticate_user!, :only => [:reset_password_sent, :password_changed, :cron_recalculate_popularity, :cron_check_outdated_boosts, :cron_regenerate_superlike, :cron_regenerate_likes, :social_login_check, :cron_randomize_bundled_users_geolocation, :cron_check_online_users, :cron_regenerate_monthly_boost, :cron_regenerate_weekly_super_sweet]


  CRON_TOKEN = "8b645d9b-2679-4a9d-a295-faa88e9dca8c"


  def reset_password_sent
    render :layout => 'devise'
  end

  def password_changed
    render :layout => 'devise'
  end


  # GET /users
  # GET /users.json
  def index
          @title = "Lista de usuarios"

              if !params[:q].nil?
                    @search = params[:q][:email_or_name_cont]
                  else
                    @search = ""
              end

          @q = User.all.ransack(params[:q])
          @users = @q.result.order("created_at DESC").paginate(:page => params[:page], :per_page => 15)
  end

  # GET /users/1
  # GET /users/1.json
  def show
    if current_user.admin?
      @user = User.find(params[:id])
    else
      @user = current_user
    end

    @title = "Mostrando usuario"
    @matches = @user.matches
    @likes = @user.incoming_likes.order(id: :desc)
    @sent_likes = @user.sent_likes.order(id: :desc)

    generate_access_token(@user.id)

    if @user.user_filter_preference
      @interests = Interest.where(id: (JSON.parse @user.user_filter_preference&.interests).values[0])
      @categories = InfoItemValue.where(id: (JSON.parse @user.user_filter_preference&.categories).values[0])
      
      @gender_preferences = UserFilterPreference.find_by(user_id: current_user.id)
    else
      @interests = []
      @categories = []
    end

    @user_main_interests = UserMainInterest.where(user_id: @user.id)

    @users = User.visible.where.not(id: @user.id)

    respond_to do |format|
      format.html # renderiza la vista normal
      format.json do
        render json: @user.as_json(
          methods: [:user_age, :user_media_url, :favorite_languages],
          include: [
            :user_media,
            :user_interests,
            :user_info_item_values,
            :user_main_interests,
            :tmdb_user_data,
            :tmdb_user_series_data,
            :user_filter_preference
          ]
        )
      end
    end
  end


  def get_user
     @user = User.find(params[:id])
    render json: @user.as_json(
    methods: [:user_age, :user_media_url, :favorite_languages],
    include: [
      :user_media,
      :user_interests,
      :user_info_item_values,
      :user_main_interests,
      :tmdb_user_data,
      :tmdb_user_series_data,
      :user_filter_preference
    ]
  )
  end


  # GET /users/new
  def new
    @user = User.new
    @title = "Crear nuevo usuario"
    @route = "/create_user"
  end

  # GET /users/1/edit
  def edit
    @title = "Editando usuario"
    @images = @user.user_media
    @edit = true
    @route = "/update_user"
  end

  # POST /users
  # POST /users.json
  def create
    @user = User.new(user_params)
    respond_to do |format|
      if @user.save
        format.html { redirect_to users_url, notice: 'User was successfully created.' }
        format.json { render :show, status: :created, location: @user }
      else
        format.html { render :new }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /users/1
  # PATCH/PUT /users/1.json
def update
  if params[:password].to_s.blank?
    params.delete(:password)
    params.delete(:password_confirmation)
  end

  @user = if params[:id]
            User.find(params[:id])
          else
            User.find(params[:user][:id])
          end

  # 1️⃣ Validar desnudez antes de actualizar
  if params[:user] && params[:user][:images].present? && params[:user][:images].is_a?(Array)
    params[:user][:images].each do |image|
      if image.is_a?(ActionDispatch::Http::UploadedFile) && detect_nudity(image)
        render json: { status: 400, message: "La imagen contiene desnudos y no puede subirse." }, status: :bad_request and return
      end
    end
  end

    # Limpieza de favorite_languages
    if params[:user] && params[:user][:favorite_languages].present?
      fav = params[:user][:favorite_languages]
      # Si es un string serializado, conviértelo a array
      if fav.is_a?(String)
        begin
          fav = JSON.parse(fav)
        rescue
          fav = fav.split(",")
        end
      end
      # Si es un array con strings serializados, conviértelo
      if fav.is_a?(Array) && fav.length == 1 && fav.first.is_a?(String) && fav.first.include?("[")
        begin
          fav = JSON.parse(fav.first)
        rescue
          fav = fav.first.split(",")
        end
      end
      # Finalmente, guarda como string separado por comas
      params[:user][:favorite_languages] = fav.join(",")
    end

  respond_to do |format|
    if @user.update(user_params)

      # 2️⃣ Subir imágenes solo si no hay desnudez
      if params[:user] && params[:user][:images].present? && params[:user][:images].is_a?(Array)
        params[:user][:images].each do |image|
          if image.is_a?(ActionDispatch::Http::UploadedFile)
            UserMedium.create!(file: image, user_id: @user.id)
          end
        end
      end

      if params[:info_item_values]
        params[:info_item_values].each do |iv|
          next if iv.blank?
          @user.user_info_item_values.create(info_item_value_id: iv)
        end
      end

      if params[:distance_range]
        @user.user_filter_preference&.update(distance_range: params[:distance_range])
      end

      if params[:gender_preferences]
        user_filter_pref = @user.user_filter_preference || @user.create_user_filter_preference
        value = params[:gender_preferences].is_a?(Array) ? params[:gender_preferences].join(",") : params[:gender_preferences]
        user_filter_pref.update(gender_preferences: value)
      end

      if params[:user_interests]
        params[:user_interests].each do |iv|
          next if iv.blank?
          @user.user_interests.create(interest_id: iv)
        end
      end

      if params[:user_main_interests]
        incoming = params[:user_main_interests]
        if !incoming.is_a?(Array) || incoming.size != 4
          render json: { error: "Debes enviar exactamente 4 intereses" }, status: :unprocessable_entity and return
        end

        incoming_ids = incoming.map { |i| i[:interest_id].to_i }
        @user.user_main_interests.where.not(interest_id: incoming_ids).destroy_all

        incoming.each do |umi|
          umi_record = UserMainInterest.find_or_initialize_by(user_id: @user.id, interest_id: umi[:interest_id])
          umi_record.percentage = umi[:percentage]
          umi_record.save
        end
      end

      format.html { redirect_to show_user_path(id: @user.id), notice: 'User was successfully updated.' }
      format.json { render 'show' }
    else
      format.html { render :edit }
      format.json { render json: @user.errors, status: :unprocessable_entity }
    end
  end
end


  # DELETE /users/1
  # DELETE /users/1.json
  def destroy
    @user.destroy
     respond_to do |format|
      format.html { redirect_to users_url, notice: 'Usuario eliminado con éxito.' }
       format.json {
          render json: {
                  notice: "User was successfully destroyed.",
                  status: 200
                }, status: 200
        }

     end
  end


  # Elimina la cuenta de un usuario (soft delete)
  def delete_account
    # Primero marcamos la cuenta como eliminada
    current_user.update!(deleted_account: true)
    
    # Luego deslogueamos al usuario
    sign_out current_user
    
    render json: { status: 200, message: "Account deleted successfully" }, status: 200
  end



  # Hace manualmente un match entre dos usuarios. (desde el admin)
  def create_match
    umr = UserMatchRequest.find(params[:id])
    umr.update(is_match: true, match_date: DateTime.now, user_ranking: umr.user.ranking, target_user_ranking: umr.target.ranking)

    twilio = TwilioController.new
    conversation_sid = twilio.create_conversation(umr.user_id, umr.target_user)
    umr.update(twilio_conversation_sid: conversation_sid)

    # Notificación push al usuario que recibe el match
    target_user = User.find(umr.user_id)
      devices = Device.where(user_id: target_user.id)
      notification = NotificationLocalizer.for(user: target_user, type: :match)
      devices.each do |device|
        if device.token.present?
          FirebasePushService.new.send_notification(
            token: device.token,
            title: notification[:title],
            body: notification[:body],
            data: { action: "match", user_id: umr.user_id.to_s },
            sound: "match.mp3",
            channel_id: "sms-channel",
            category: "match" # Asegúrate de que esta category esté registrada en tu app iOS
          )
        end
      end

    redirect_to show_user_path(id: umr.target_user), notice: 'Match generado con éxito.'
  end

  def send_phone_verification
  code = rand(100000..999999).to_s
  current_user.update(
    phone: params[:phone],
    phone_verification_code: code,
    phone_verification_sent_at: Time.now
  )
  TwilioService.send_sms(params[:phone], "Tu código de verificación es: #{code}")
  render json: { status: 200, message: "Código enviado" }
end

def verify_phone_code
  if current_user.phone_verification_code == params[:code] &&
     current_user.phone_verification_sent_at > 10.minutes.ago
    current_user.update(phone_validated: true, phone_verification_code: nil)
    render json: { status: 200, message: "Teléfono validado" }
  else
    render json: { status: 400, message: "Código incorrecto o expirado" }
  end
end


  # Hacer manualmente like entre dos users (desde el admin)
    def create_like
      umr = UserMatchRequest.find_by(user_id: params[:user_id], target_user: params[:target_user])
      
      unless umr
        umr = UserMatchRequest.create(
          user_id: params[:user_id],
          target_user: params[:target_user],
          is_like: true,
          is_rejected: false,
          is_superlike: false
        )
      end

      target_user = User.find(umr.target_user)
      devices = Device.where(user_id: target_user.id)
      notification = NotificationLocalizer.for(user: target_user, type: :like)

      devices.each do |device|
        if device.token.present?
          FirebasePushService.new.send_notification(
            token: device.token,
            title: notification[:title],
            body: notification[:body],
            data: {
              action: "like",
              user_id: umr.user_id.to_s
            },
            sound: "sms.mp3", 
            channel_id: "sms-channel"              # <- para que suene (debe estar en la app)
            )
          
        end
      end

      redirect_to show_user_path(id: umr.user_id), notice: 'Like generado con éxito.'
    end

  # Deshacer un match desde el admin
  def unmatch
    # Buscar el match en ambas direcciones
    umr = UserMatchRequest.find_by(
      user_id: params[:user_id],
      target_user: params[:target_user],
      is_match: true
    ) || UserMatchRequest.find_by(
      user_id: params[:target_user],
      target_user: params[:user_id],
      is_match: true
    )

    unless umr
      redirect_to show_user_path(id: params[:user_id]), alert: 'Match no encontrado.'
      return
    end

    # Eliminar la conversación de Twilio si existe
    if umr.twilio_conversation_sid.present?
      begin
        twilio = TwilioController.new
        twilio.destroy_conversation(umr.twilio_conversation_sid)
      rescue => e
        Rails.logger.error "Error eliminando conversación de Twilio: #{e.message}"
      end
    end

    # Eliminar el match
    umr.destroy

    # También eliminar el match inverso si existe
    inverse_umr = UserMatchRequest.find_by(
      user_id: umr.target_user,
      target_user: umr.user_id,
      is_match: true
    )
    inverse_umr&.destroy

    redirect_to show_user_path(id: params[:user_id]), notice: 'Match eliminado con éxito.'
  end



  def block
    @user.blocked = !@user.blocked
    respond_to do |format|
      if @user.save
        format.html { redirect_to @user, notice: 'User was successfully blocked.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end


  # Método para actualizar la geolocalización de un usuario.
  def update_location
     # logger.info "USER::"+current_user.inspect
      location_city = nil
      location_country = nil


      if current_user.location_city.present? and !params[:location_country]
        render json: { status: 200, message: "Location updated"}, status: 200
        return
      end



      if params[:location_city] and params[:location_city] != "current_geolocation"
        location_city = params[:location_city]
      end

      if params[:location_country] and params[:location_country] != "current_geolocation"
        location_country = params[:location_country]
      end



      current_user.update(lat: params[:lat], lng: params[:lng], location_city: location_city, location_country: location_country)
      render json: { status: 200, message: "Location updated"}, status: 200
  end


  # Devuelve los boost, superlikes, etc del usuario.
  def get_user_consumables
    #jbuilder
  end

  def resolve_location
  lat = params[:lat]
  lng = params[:lng]
  if lat.blank? || lng.blank?
    render json: { error: "lat y lng son requeridos" }, status: 400 and return
  end

  url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=#{lat}&lon=#{lng}"
  response = HTTParty.get(url, headers: { "User-Agent" => "YourAppName" })

  if response.success? && response['address']
    address = response['address']
    city = address['city'] || address['town'] || address['village'] || address['hamlet']
    country = address['country']
    render json: { city: city, country: country }
  else
    render json: { error: "No se pudo resolver la ubicación" }, status: 422
  end
end

  # Método para usar un boost
  def use_boost

      logger.info current_user.inspect
      if current_user.high_visibility
        render json: { status: 406, error: "Ya tienes un power sweet activo"}, status: 406
        return
      end

      if current_user.use_boost
        render json: "OK".to_json
      else
        render json: { status: 405, error: "No te quedan power sweet"}, status: 405
      end
  end

  def time_to_end_boost
    has_boost = current_user.time_to_end_boost != nil
    return render json: { time: current_user.time_to_end_boost, has_boost: has_boost, now: Time.now}
  end


  # Método que te dice si tienes likes
  def have_i_likes
    if current_user.has_likes
      render json: "OK".to_json
    else
      render json: { status: 400, error: "No tiene likes"}, status: 400
    end
  end


  # Regenera los superlikes de los usuarios (1 cada 24h)
  def cron_regenerate_superlike
    unless params[:token] == CRON_TOKEN
      render plain: "Unauthorized", status: :unauthorized and return
    end 
    User.where(superlike_available: 0, current_subscription_name: nil).where("last_superlike_given <= ?", DateTime.now-7.days).update_all(superlike_available:1)
    User.where(superlike_available: 0).where.not(current_subscription_name: nil).where("last_superlike_given <= ?", DateTime.now-7.days).update_all(superlike_available:5)

    render json: "OK".to_json
  end
 
  # Método para validar a los usuarios online cada 30 segundos  
  def cron_check_online_users
      unless params[:token] == CRON_TOKEN
    render plain: "Unauthorized", status: :unauthorized and return
      end    
    User.where(last_connection: false).update(is_connected: false)
    User.where(last_connection: DateTime.now-100.years..DateTime.now-30.seconds).update(is_connected: false)
    render json: { status: "OK" }
  end

# Método cron para quitar el high_visibility a aquellos usuarios que lo tengan caducado.
def cron_check_outdated_boosts
  unless params[:token] == CRON_TOKEN
    render plain: "Unauthorized", status: :unauthorized and return
  end    

  users = User.where(high_visibility: true).where("high_visibility_expire <= ?", DateTime.now)

  users.each do |user|
    user.update(high_visibility: false)

    user.devices.each do |device|
      next if device.token.blank?
      FirebasePushService.new.send_notification(
        token: device.token,
        title: "Tu power sweet ha caducado",
        body: "Tu power sweet ha caducado, ya no estás en la parte superior de la lista de usuarios.",
        data: { action: "boost_expired" }
      )
    end
  end

  render json: "OK".to_json
end
  
def cron_regenerate_monthly_boost
  unless params[:token] == CRON_TOKEN
    render plain: "Unauthorized", status: :unauthorized and return
  end

  User.where(current_subscription_name: ['premium', 'supreme']).find_each do |user|
    last_boost = user.last_monthly_boost_given || DateTime.new(2000)
    if last_boost < Date.today.beginning_of_month
      user.update(
        boost_available: user.boost_available.to_i + 1,
        last_monthly_boost_given: DateTime.now
      )
    end
  end

  render json: "OK".to_json
end


  # Método cron para que te devuelva los likes cada 12h.
  def cron_regenerate_likes
    unless params[:token] == CRON_TOKEN
      render plain: "Unauthorized", status: :unauthorized and return
    end
    users = User.where("last_like_given <= ?", DateTime.now-12.hours)

    users.each do |user|
      if user.likes_left == 0
        user.devices.each do |device|
          next if device.token.blank?
          FirebasePushService.new.send_notification(
            token: device.token,
            title: "¡Ya puedes empezar a toppitear de nuevo!",
            body: "",
            data: { action: "likes_regenerated" }
          )
        end
      end
      user.update(likes_left: 55)
    end


    render json: "OK".to_json
  end


    # Regenera 5 super_sweet a los usuarios premium o supreme una vez por semana
  def cron_regenerate_weekly_super_sweet
    unless params[:token] == CRON_TOKEN
      render plain: "Unauthorized", status: :unauthorized and return
    end

    User.where(current_subscription_name: ['premium', 'supreme']).find_each do |user|
      last_weekly_super_like = user.last_superlike_given || DateTime.new(2000)
      if last_weekly_super_like < Date.today.beginning_of_week
        user.update(
          superlike_available: +5,
          last_superlike_given: DateTime.now
        )
      end
    end

    render json: "OK".to_json
  end

  # Cron que recalcula la popularidad de los usuarios
  def cron_recalculate_popularity
     User.active.each do |user|
      user.recalculate_popularity
     end
     render json: "OK".to_json
  end

  # Cron to move bundled users geolocation randomly
  def cron_randomize_bundled_users_geolocation
    # Verify cron call
    head :unauthorized and return if CRON_TOKEN != params["token"]

    starting_time = DateTime.now

    # Coordinates for every city of interest
    # Important: the area must be a triangle
    coordinates = {
      valencia: {
          polygon: [
              [39.45599951395697, -0.35774534080641596],
              [39.70153979085093, -0.28551053838684476],
              [39.44312753496985, -0.7541106669035501]
          ]
      },
      madrid: {
          polygon: [
              [40.326276925728266, -3.694195434504355],
              [40.42014600870334, -3.7946299451347385],
              [40.46663764699618, -3.6175752923739593]
          ]
      },
      barcelona: {
          polygon: [
              [41.48428667221768, 2.0676541643237862],
              [41.456465117739356, 2.2527667891573264],
              [41.37947255632443, 2.1781018097244207]
          ]
      }
    }

    # Set min/max lat/lng
    lat_values = []
    lng_values = []

    min_lat = 0
    max_lat = 0
    min_lng = 0
    max_lng = 0

    coordinates = coordinates[:valencia][:polygon].flatten

    coordinates.each_with_index do |coordinate, index|

        if index.even?
            lat_values.push(coordinate)
        else
            lng_values.push(coordinate)
        end
    end

    min_lat = lat_values.min
    max_lat = lat_values.max
    min_lng = lng_values.min
    max_lng = lng_values.max

    users = User.bundled

    users.each do |user|
      rand_lat = rand(min_lat..max_lat).round(7).to_s
      rand_lng = rand(min_lng..max_lng).round(7).to_s
      user.update(lat: rand_lat, lng: rand_lng)
    end

    finish_time = DateTime.now

    render json: {
      cron: "cron_randomize_bundled_users_geolocation",
      status: :ok,
      job_started: starting_time,
      job_ended: finish_time
      }, status: 200

  end

  def rollback
    target_user_id = params[:target_user_id]
    
    unless target_user_id.present?
      render json: { status: 400, message: "target_user_id es requerido" }, status: :bad_request
      return
    end

    # Buscar la interacción más reciente del usuario actual con el target_user
    interaction = UserMatchRequest.where(
      user_id: current_user.id,
      target_user: target_user_id
    ).order(created_at: :desc).first

    unless interaction
      render json: { status: 404, message: "No se encontró interacción para deshacer" }, status: :not_found
      return
    end

    # Eliminar la interacción
    interaction.destroy

    render json: { 
      status: 200, 
      message: "Swipe deshecho correctamente",
      target_user_id: target_user_id.to_i
    }
  end

  def toggle_visibility
      current_user.toggle :hidden_by_user
      current_user.save

      render json: { status: 200, message: current_user.hidden_by_user }, status: 200
  end


  # Desactivar publi, solo usuarios premium
def toggle_publi
  # Verificar si el usuario tiene suscripción premium o supreme
  if current_user.current_subscription_name.in?(['premium', 'supreme'])
    current_user.toggle :show_publi
    current_user.save
    render json: { status: 200, message: current_user.show_publi }, status: 200
  else
    render json: { status: 400, message: "User is not premium" }, status: 400
  end
end


  # Método para reordenar las imágenes de un usuario
  def reorder_images
    params[:images].each_with_index do |image_id, index|
      UserMedium.find(image_id).update(position: index)
    end
    render json: "OK".to_json
  end



  # User swipes, la madre del cordero. El que te devuelve todos los usuarios.
  def user_swipes

    
    if current_user.show_publi
       @publis = Publi.active_now
    else
      @publis = []
    end

    Rails.logger.info @publis.inspect

      # IDs de usuarios ocultos
    hidden_user_ids = User.where(hidden_by_user: true).pluck(:id)


    deleted_user_ids = User.where(deleted_account: true).pluck(:id)

    # De esos ocultos, cuáles ME han dado like (user_id es quien da el like)
    hidden_who_liked_me = UserMatchRequest.where(user_id: hidden_user_ids, target_user: current_user.id, is_like: true).pluck(:user_id)

    # Ocultos que NO me han likeado -> hay que excluirlos
    hidden_to_exclude = hidden_user_ids - hidden_who_liked_me

    users_to_exclude_basic = hidden_to_exclude + deleted_user_ids

    # Resultado: todos los usuarios excepto esos ocultos que no me han likeado
    users = User.where.not(id: hidden_to_exclude)
    # Si no tiene ninguna foto, le vamos a tirar un KO para que complete su perfil.
    if !current_user.user_media.any?
        render json: { status: 405, message: "Debes completar tu perfil con al menos una foto para poder ver a otros usuarios."}, status: 405
        return
    end

    
    current_user_id = current_user.id
    filter_preference = UserFilterPreference.find_by(user_id: current_user_id)



    # Calculamos rango de fechas de nacimiento posibles para el filtro edad.
    start_date = Date.today - (filter_preference&.age_till || 0).years
    end_date = Date.today -  (filter_preference&.age_from || 0).years

    # Comprobamos filtro género. Si el valor es 2, son todos los géneros.
    # Freeze lat lng to be able to see some shit everywhere
    # current_user.lat = "39.4676626"
    # current_user.lng = "-0.381093"

    # Extraemos el género del usuario actual
    my_gender = current_user.gender

    # Buscamos ids de usuario que estén buscando el género de nuestro usuario
    sql = <<-SQL
      SELECT user_id
      FROM user_filter_preferences
      WHERE
        (
          gender_preferences = '#{my_gender}' OR
          gender_preferences LIKE '#{my_gender},%' OR
          gender_preferences LIKE '%,#{my_gender}' OR
          gender_preferences LIKE '%,#{my_gender},%' OR
          gender_preferences LIKE '%non_binary%'
        )
        AND user_id != #{current_user_id}
    SQL

    user_ids = ActiveRecord::Base.connection.exec_query(sql)

    users = User.where(id: user_ids.map { |u| u["user_id"] })

        # Filtro por el género que yo busco
    if filter_preference.gender_preferences.present?
      users = users.where(gender: filter_preference.gender_preferences.split(","))
    end

        # 🚨 Aquí metemos el filtro de verificación
    if filter_preference.only_verified_users
      users = users.where(verified: true)
    end


    limit_users_per_swipe = 20
    users = users.active.visible.near([current_user.lat, current_user.lng], filter_preference.distance_range, order: 'id')


    logger.info "USERS0"
   # logger.info users.inspect

    # IDs de usuarios a los que el current_user ha dado LIKE o DISLIKE.
    # Estas son interacciones que el current_user ha INICIADO.
    my_sent_interactions = UserMatchRequest.where(user_id: current_user_id).pluck(:target_user)

    # IDs de usuarios que han interactuado con el current_user (LIKE o DISLIKE)
    # y cuya interacción el current_user YA HA PROCESADO (es decir, ya se hizo match o ya se rechazó).
    my_received_processed_interactions = UserMatchRequest.where(target_user: current_user_id)
                                                       .where("is_match = ? OR is_rejected = ?", true, true)
                                                       .pluck(:user_id)

    # NUEVO: IDs de usuarios que yo he rechazado
    my_rejected = UserMatchRequest.where(user_id: current_user_id, is_rejected: true).pluck(:target_user)

    # NUEVO: IDs de usuarios que me han rechazado
    rejected_me = UserMatchRequest.where(target_user: current_user_id, is_rejected: true).pluck(:user_id)

    # Combinamos todas las IDs de usuarios que no deberían volver a aparecer.
    # Esto incluye a los que yo descarté/gusteé y a los que me gustaron/descartaron
    # y ya procesé la interacción.
    users_to_exclude = (my_sent_interactions + my_received_processed_interactions + my_rejected + rejected_me).uniq

    # MUY IMPORTANTE: Asegúrate de que el propio usuario (current_user) no se incluya en los resultados.
    users_to_exclude << current_user_id

    logger.info "USUARIOS A EXCLUIR: " + users_to_exclude.inspect

    # Aplicamos el filtro para excluir a todos estos usuarios de la lista.
    users = users.where.not(id: users_to_exclude)

    # IDs de usuarios bloqueados por el usuario actual (complaints)
    blocked_user_ids = Complaint.where(user_id: current_user_id).pluck(:to_user_id)
    users_to_exclude += blocked_user_ids
    users_to_exclude = users_to_exclude.uniq

    logger.info "USUARIOS A EXCLUIR: " + users_to_exclude.inspect

    # Aplicamos el filtro para excluir a todos estos usuarios de la lista.
    users = users.where.not(id: users_to_exclude)

    # Edad
    if filter_preference.age_from.present? and filter_preference.age_till.present?
       users = users.born_between(start_date, end_date)
    end




    user_ids = users.pluck(:id)


    logger.info "IDS 1"
    logger.info user_ids.inspect

    user_with_interests = []

    # Intereses
    if filter_preference.interests.present?

        interests = JSON.parse filter_preference.interests

        interests = interests["interests"] # Ñapa del front

        if interests.any?
          UserMainInterest.where(interest_id: interests, user_id: user_ids).pluck(:user_id).each do |id|
            user_with_interests << id
          end
        end

    end


    # Categorías
    if filter_preference.categories.present?
      categories = JSON.parse filter_preference.categories
      categories = categories["categories"]

      if categories.any?
        user_ids = UserInfoItemValue.where(info_item_value_id: categories, user_id: user_ids).pluck(:user_id)
      end
    end


  if filter_preference.interests.present?
    interests = JSON.parse(filter_preference.interests)["interests"] rescue []
    if interests.any?
      # 1. Buscar primero en user_main_interests
      main_interest_ids = UserMainInterest.where(interest_id: interests, user_id: user_ids).pluck(:user_id)
      if main_interest_ids.any?
        user_with_interests = main_interest_ids.uniq
        user_ids = user_with_interests
      else
        # 2. Si no hay ninguno, buscar en user_interests
        secondary_interest_ids = UserInterest.where(interest_id: interests, user_id: user_ids).pluck(:user_id)
        if secondary_interest_ids.any?
          user_with_interests = secondary_interest_ids.uniq
          user_ids = user_with_interests
        else
          user_ids = []
        end
      end
    end
end


    logger.info "IDS 2"
    logger.info user_ids.inspect


    users = User.where(id: user_ids)



    users_with_boost = users.where(high_visibility: true).pluck(:id).shuffle
    users_without_boost = users.where(high_visibility: false).pluck(:id).shuffle


    # Añadimos los likes al principio, para ello los extraemos
    incoming_likes = current_user.incoming_likes.pluck(:user_id)

    # Filtra los incoming_likes para que no estén en users_to_exclude
    incoming_likes = incoming_likes.reject { |il| users_to_exclude.include?(il) }

    # 🚨 NUEVO: Filtrar incoming_likes por criterios básicos (distancia, edad, género)
    if incoming_likes.any?
      incoming_likes_filtered = User.where(id: incoming_likes)
        .where(gender: filter_preference.gender_preferences.split(",")) # género
        .active.visible
            
      # Filtro de edad si está definido
      if filter_preference.age_from.present? && filter_preference.age_till.present?
        incoming_likes_filtered = incoming_likes_filtered.born_between(start_date, end_date)
      end
      
      # Filtro de verificación
      if filter_preference.only_verified_users
        incoming_likes_filtered = incoming_likes_filtered.where(verified: true)
      end
      
      incoming_likes = incoming_likes_filtered.pluck(:id)
    end

    if incoming_likes.count > 1
        # mezclamos y eliminamos uno para el sugar play
          incoming_likes = incoming_likes.shuffle
          incoming_likes.shift
        #
    end


    user_ids = users_with_boost + users_without_boost


    logger.info "USER IDS 4::"+user_ids.inspect


    # Lo que hacemos ahora es recorrer los likes que tiene un usuario e intercalarlos en las primeras 30 posiciones del array final.
    # Esto se hace de manera aleatoria.
    incoming_likes.each_with_index do |il, index|

      # get random number between 0 and 30
      random = rand(6..35)

      # insert il in that position
      user_ids.insert(random, il)

    end

    #if incoming_likes.any?
     # logger.info "FIRE INCOMING"
      #user_ids.prepend incoming_likes.first
    #end

    user_ids = user_ids.take(35)

    logger.info "IDS 3 "+current_user.id.to_s
    logger.info user_ids.inspect

    # Match Request ya lanzados. Descartamos users que ya hemos dado like o dislike
    discarded_users = UserMatchRequest.where(user_id: current_user.id).pluck(:target_user)


    # Filtro final, SOLO este, no vuelvas a filtrar por discarded_users después
    @users = User.includes(:user_info_item_values, :user_interests, :user_media, :user_main_interests)
            .where(id: user_ids)
            .where.not(id: users_to_exclude)
            .sort_by {|m| user_ids.index(m.id)}
    logger.info "USERS FINAL"
    
    if !@users.any? or @users.count < 30
      @users = User.includes(:user_info_item_values, :user_interests, :user_media, :user_main_interests)
               .where(id: user_ids)
               .where.not(id: current_user_id)
               .sort_by {|m| user_ids.index(m.id)}
    end
    
render json: {
  users: @users.as_json(
    methods: [:user_age, :user_media_url],
    include: [
      :user_media,
      :user_interests,
      :user_info_item_values,
      :user_main_interests,
      :tmdb_user_data,
      :tmdb_user_series_data # <-- añade esto
    ]
  )}

=begin

    @users = User.where(id: user_ids).where.not(id: current_user_id)
    users_ranking = @users.pluck(:id, :ranking)

    pond = []

    min = ( current_user.ranking / 2 ) - 0.1
    track_1 = current_user.ranking.to_f
    track_2 = ( current_user.ranking * 1.5 ) - 0.1
    max = 100.to_f


    # Pendiente contemplar los likes / dislikes para las probabilidades

    @users.each do |user|

      case user.ranking.to_f

      when 0..min # Tramo 0
        pond << [user.id,  10 ]


      when min..current_user.ranking.to_f # Tramo 1

        pond << [user.id,  20 ]


      when (current_user.ranking+0.01)..track_2 # Tramo 2

        pond << [user.id,  50 ]


      when (track_2+0.1)..max # Tramo 3, máximo
        pond << [user.id,  15 ]
      end

    end

    logger.info pond.inspect

    number = @users.count

    pickup = Pickup.new(pond, uniq: true)
    ids = pickup.pick(12)

    ids = ids.shuffle




    @users = User.includes(:user_info_item_values).where(id: ids)

=end


   # render 'index'
    # render json: @users.as_json(methods: [:user_age, :user_media_url], :include => [:user_media])
  end

# GET /users/available_publis
def available_publis
  Rails.logger.info "=== DEBUG PUBLIS ==="
  
  # 1. Ver la lista de publicidades disponibles
  all_active = Publi.active_now
  Rails.logger.info "Todas las publis activas: #{all_active.map(&:id).inspect}"

  if all_active.empty?
    render json: { status: 404, message: "No hay publicidades disponibles" }, status: 404
    return
  end

  # 2. Comprobar registros pendientes (sin vista) del usuario
  pending_records = current_user.user_publis.where(viewed: false)
  pending_publi_ids = pending_records.pluck(:publi_id)
  Rails.logger.info "Registros pendientes: #{pending_publi_ids.inspect}"

  # 3. Crear registros para publicidades que no los tengan + actualizar fechas de los existentes
  all_active.each do |publi|
    existing_record = current_user.user_publis.find_by(publi_id: publi.id, viewed: false)
    
    if existing_record
      # Si ya existe, actualizar fecha
      existing_record.update(updated_at: Time.current)
      Rails.logger.info "Actualizada fecha del registro para publi #{publi.id}"
    else
      # Si no existe, crear nuevo registro
      current_user.user_publis.create(publi_id: publi.id, viewed: false)
      Rails.logger.info "Creado nuevo registro para publi #{publi.id}"
    end
  end

  # 4. Ordenar de manera aleatoria pero con la última vista al final
  last_viewed_record = current_user.user_publis.where(viewed: true).order(updated_at: :desc).first
  last_viewed_publi_id = last_viewed_record&.publi_id
  Rails.logger.info "Última publi vista: #{last_viewed_publi_id}"

  # Separar la última vista del resto
  other_publis = all_active.reject { |publi| publi.id == last_viewed_publi_id }
  last_viewed_publi = all_active.find { |publi| publi.id == last_viewed_publi_id }

  # Mezclar las otras de forma aleatoria
  shuffled_publis = other_publis.shuffle

  # Agregar la última vista al final (si existe)
  ordered_publis = last_viewed_publi ? shuffled_publis + [last_viewed_publi] : shuffled_publis
  
  Rails.logger.info "Orden final de publis: #{ordered_publis.map(&:id).inspect}"

  # 5. Enviar las publicidades al front
  publi_url = "https://web-backend-ruby.uao3jo.easypanel.host"

  render json: {
    status: 200,
    publis: ordered_publis.as_json.map { |publi| publi.merge("image_url" => "#{publi_url}#{publi['image_url']}")}
  }
end
 
# PUT /users/mark_publi_viewed  
def mark_publi_viewed
  Rails.logger.info "Current user: #{current_user.inspect}"
  Rails.logger.info "Publi ID recibido: #{params[:publi_id]}"

  unless current_user
    render json: { status: 401, message: "Usuario no autenticado" }, status: 401
    return
  end

  unless params[:publi_id]
    render json: { status: 400, message: "publi_id es requerido" }, status: 400
    return
  end

  # Buscar el registro específico de esta publi para este usuario
  user_publi_record = current_user.user_publis.find_by(publi_id: params[:publi_id], viewed: false)
  
  unless user_publi_record
    render json: { status: 404, message: "No se encontró registro pendiente para esta publi" }, status: 404
    return
  end

  # Marcar como vista el registro específico y actualizar fecha
  user_publi_record.update(viewed: true, updated_at: Time.current)
  
  Rails.logger.info "Registro marcado como visto: #{user_publi_record.inspect}"
  
  if user_publi_record.viewed?
    # Contar cuántas veces ha visto esta publi específica
    view_count = current_user.user_publis.where(publi_id: params[:publi_id], viewed: true).count
    Rails.logger.info "Usuario #{current_user.id} ha visto la publi #{params[:publi_id]} un total de #{view_count} veces"
    
    render json: { 
      status: 200, 
      message: "Publi marcada como vista", 
      publi_id: params[:publi_id].to_i,
      view_count: view_count 
    }
  else
    Rails.logger.error "Error marcando registro como visto: #{user_publi_record.errors.inspect}"
    render json: { status: 500, message: "Error al marcar el registro como visto" }, status: 500
  end
end

# GET /users/get_banner
def get_banner
  Rails.logger.info "=== GET BANNER REQUEST ==="
  Rails.logger.info "Current user: #{current_user.id}"

  unless current_user
    render json: { status: 401, message: "Usuario no autenticado" }, status: 401
    return
  end

  # Obtener todos los banners activos y vigentes
  active_banners = Banner.active_now
  Rails.logger.info "Banners activos: #{active_banners.map(&:id).inspect}"

  if active_banners.empty?
    render json: { status: 404, message: "No hay banners disponibles" }, status: 404
    return
  end

  # Obtener banners que el usuario NO ha visto
  viewed_banner_ids = current_user.banner_users.pluck(:banner_id)
  unseen_banners = active_banners.where.not(id: viewed_banner_ids)
  
  Rails.logger.info "Banners no vistos: #{unseen_banners.map(&:id).inspect}"

  # Si no hay banners sin ver, tomar uno aleatorio de todos los activos
  banner_to_show = if unseen_banners.any?
                     unseen_banners.sample
                   else
                     active_banners.sample
                   end

  Rails.logger.info "Banner seleccionado: #{banner_to_show.id}"

  # Marcar automáticamente como visto
  banner_to_show.mark_as_viewed_by(current_user)
  Rails.logger.info "Banner marcado como visto para usuario #{current_user.id}"

  # URL base igual que en available_publis
  banner_url = "https://web-backend-ruby.uao3jo.easypanel.host"

  render json: {
    status: 200,
    banner: banner_to_show.as_json.merge("image_url" => "#{banner_url}#{banner_to_show.image.url}")
  }
end

  # High popularity profiles (vip toppins)
def get_vip_toppins

    #current_user = User.find(177)
    to_remove = []

    to_remove = to_remove + current_user.sent_likes.pluck(:target_user)

    to_remove = to_remove + UserMatchRequest.where(target_user: current_user.id, is_match: true).pluck(:user_id)

    # TEAM TOPPIN FIX
    to_remove << 606 # Añadimos el team toppin al array de id's a eliminar

    # Extraemos el género del usuario actual
    my_gender = current_user.gender
    my_gender_preference = current_user.user_filter_preference.gender_preferences

    # Buscamos ids de usuario que estén buscando el género de nuestro usuario
    user_ids = UserFilterPreference
      .where("gender_preferences IS NULL OR gender_preferences = '' OR gender_preferences LIKE ?", "%#{my_gender}%")
      .pluck(:user_id)

      logger.info "GENDER PREFERENCE "+my_gender_preference
      # Si tiene preferencia de genero, busco solo usuarios de ese genero.
      users = User.where(id: user_ids, gender: my_gender_preference)



    @users = users.visible.where.not(id: to_remove).order(ratio_likes: :desc).limit(6)


    unlocked = current_user.user_vip_unlocks.pluck(:target_id)

      @users.each do |user|

          if unlocked.include? user.id
            user.unlocked = true
          else
            user.unlocked = false
          end

      end

      render 'index'
  end



  # Registrar dispositivo para notificaciones push.
  def register_device
    # Si el usuario existe en la base de datos, registramos dispositivo
    if current_user
      d = Device.register(params[:token], params[:so].downcase, params[:device_uid], current_user)
      render json: {status: 200, device: d}.as_json
    else
     render json: { status: 401, error: "Error registrando dispositivo, usuario no encontrado."}, status: 401
    end
  end



  # Método para la tirada de ruleta.
  def spin_roulette
    if current_user.spin_roulette_available == 0
      render json: { status: 405, message: "No te quedan tiradas" }, status: 405
      return
    end

    # Número de tirada (contando la actual)
    spin_count = current_user.spin_number || 0
    spin_count += 1

    # Define el pond normal según tu lógica
    if current_user.last_roulette_played.nil?
      pond = {
        "donut"  => 0,
        "heart" => 0,
        "muffin"  => 0,
        "card" => 0,
        "star" => 100,
        "bear" => 0,
        "battery" => 0
      }
    else
      if current_user.incoming_likes.count > 0
        pond = {
        "donut": 5,
        "muffin": 5,
        "bear": 5,
        "heart": 22,
        "card": 21,
        "star": 21,
        "battery": 21
      }
      else
        pond = {
          "donut"  => 0,
          "heart" => 25,
          "muffin"  => 0,
          "card" => 25,
          "star" => 25,
          "bear" => 0,
          "battery" => 25
        }
      end
    end

    available = current_user.spin_roulette_available - 1
    current_user.update(
      last_roulette_played: DateTime.now,
      spin_roulette_available: available,
      spin_number: spin_count
    )

    pickup = Pickup.new(pond)
    result = pickup.pick(1)

    # Guarda la tirada en el historial si quieres mantener el historial
    # RoulettePlay.create!(
    #   user_id: current_user.id,
    #   spin_number: spin_count,
    #   result: result
    # )

    if result == "star"
      current_user.increase_consumable("superlikes", 1)
    end

    if result == "battery"
      current_user.increase_consumable("boosters", 1)
    end

    if result == "heart"
      current_user.increase_consumable("likes", 10)
    end

    render json: result.to_json
  end

  def validate_image
    Rails.logger.info "===> Entrando en validate_image"
    Rails.logger.info "Params recibidos: #{params.inspect}"

    current_user.update!(verification_image: params[:data][:verification_image])
    img_file = current_user.verification_image.file
    Rails.logger.info "Imagen guardada en el usuario: #{img_file.inspect}"

    response = HTTParty.post(
      "https://web-face-detection.uao3jo.easypanel.host/verify",
      body: { file: img_file },
      headers: { "Content-Type" => "multipart/form-data" }
    )
    Rails.logger.info "Respuesta de la API de verificación: #{response.inspect}"

    result = response.parsed_response
    Rails.logger.info "Resultado parseado: #{result.inspect}"

    if result["verified"]
      Rails.logger.info "Imagen verificada correctamente"
      current_user.update(verified: true)
      render json: { status: 200, message: "OK 🤘" }, status: :ok
    else
      Rails.logger.info "Imagen NO verificada, eliminando imagen del usuario"
      current_user.verification_image.remove! if current_user.verification_image.present?
      current_user.update(verification_image: nil)
      render json: { status: 400, message: "KO" }, status: :bad_request
    end
  end

  def detect_nudity(image)
  # Si es base64 (app)
  if image.is_a?(String) && image.start_with?('data:image')
    # Extrae el base64 puro
    base64_data = image.split(',')[1]
    bytes = Base64.decode64(base64_data)
  # Si es archivo físico (web)
  elsif image.respond_to?(:tempfile)
    file = image.tempfile
    file.rewind
    safe_image = MiniMagick::Image.open(file.path)
    safe_image.format("jpg") do |c|
      c.quality "90"
      c.strip
    end
    bytes = File.open(safe_image.path, 'rb') { |f| f.read }
  else
    return false
  end

  credentials = Aws::Credentials.new(
    ENV['AWS_ACCESS_KEY_ID'],
    ENV['AWS_SECRET_ACCESS_KEY']
  )

  client = Aws::Rekognition::Client.new(
    region: ENV['AWS_REGION'],
    credentials: credentials
  )

  resp = client.detect_moderation_labels({
    image: { bytes: bytes },
    min_confidence: 1.0
  })

  nude = resp.moderation_labels.select do |label|
    label.name == "Explicit Nudity" && label.confidence > 50
  end

  nude.any?
end

  # Enviamos algunos datos al chat para un array de users
  def short_info_chat

    #ids = JSON.parse params[:users]
    @users = User.where(id:params[:users])


  end


  # Comprobamos si un usuario existe via login en redes sociales y le hacemos el login.
  def social_login_check

    @user = false

      if params[:email]
        @user = User.find_by(email: params[:email])
      elsif params[:apple_token]
          @user = User.find_by(social_login_token: params[:apple_token])
      end

      if @user
        sign_in(@user)
        render 'show'
      else

        at = AppleToken.find_by(token: params[:apple_token])
        if at
          render json: { status: 405, email: at.email }, status: 405
        else
          render json: { status: 400, message: "User not exist"}, status: 400
        end
      end
  end


  # Método que actualiza los artistas de spotify del usuario
  def update_spotify

      if params[:spotify].present? # Si nos llegan datos
          spotis = params[:spotify]

          spotis.each_with_index do |spoty,index|

            indice = index + 1
            current_user["spoty"+indice.to_s] = spoty[:image]
            current_user["spoty_title"+indice.to_s] = spoty[:name]
            if indice == 6
              break
            end

          end


        else # Si llega vacío el parámetro, eliminamos todos.
          for a in 1..6 do
            current_user["spoty"+a.to_s] = nil
            current_user["spoty_title"+a.to_s] = nil
          end
        end

        current_user.save
        render json: "OK".to_json
  end


  # Actualiza las preferencias de notificaciones push
  def update_push_preferences
     current_user[params[:push_option]] = params[:value]
     current_user.save!
     render json: "OK".to_json
  end


  # Desbloquea un vip toppin (si eres premium, max 6 por semana)
  def unlock_vip_toppin

    if current_user.is_premium and current_user.user_vip_unlocks.count < 6

        current_user.user_vip_unlocks.create(target_id: params[:target_id])
        render json: "OK".to_json

    else
      render json: { status: 405, message: "Not allowed"}, status: 405
    end

  end



  def logout
    current_user.update(is_connected: false)
    sign_out current_user
    respond_to do |format|
        format.html { redirect_to root_path }
        format.json { render json: "OK".to_json }
    end
  end


  # Actualiza la conversación actual del usuario para no mandarle push si está dentro de la misma.
  def update_current_conversation
    current_user.update(current_conversation: params[:current_conversation])
    render json: "OK".to_json
  end

  # GET /users/:id/matches_status
  def matches_status
    user = User.find(params[:id])
    # Suponiendo que los matches son bidireccionales y quieres ambos lados:
    match_requests = UserMatchRequest.where("(user_id = :id OR target_user = :id) AND is_match = true", id: user.id)
    match_user_ids = match_requests.map { |mr| mr.user_id == user.id ? mr.target_user : mr.user_id }
    matches = User.where(id: match_user_ids)
    online_ids = redis.smembers("online_users").map(&:to_i)
    result = matches.map do |match|
      {
        id: match.id,
        name: match.name,
        online: online_ids.include?(match.id)
      }
    end
    render json: { matches: result }
  end

  def cron_update_vip_toppins
  unless params[:token] == CRON_TOKEN
    render plain: "Unauthorized", status: :unauthorized and return
  end

  week_start = Date.today.beginning_of_week
  VipToppin.where(week_start: week_start).delete_all

  top_users = User
    .joins("INNER JOIN user_match_requests ON users.id = user_match_requests.user_id OR users.id = user_match_requests.target_user")
    .where("user_match_requests.is_match = true AND user_match_requests.match_date >= ?", week_start)
    .group("users.id")
    .order("COUNT(user_match_requests.id) DESC")
    .limit(12)

  top_users.each do |user|
    VipToppin.create(user: user, week_start: week_start)
  end

  render plain: "VIP Toppins actualizados para la semana que empieza en #{week_start}"
end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    # Only allow a list of trusted parameters
    def user_params
      params.require(:user).permit(
        :id, :email, :name, :password, :password_confirmation, :user_name, :blocked,
        :current_subscription_id, :show_publi, :current_subscription_name, :verified,
        :verification_file, :push_token, :device_id, :device_platform, :description,
        :gender, :high_visibility, :hidden_by_user, :is_connected, :last_connection,
        :last_match, :is_new, :activity_level, :birthday, :born_in, :living_in,
        :locality, :country, :lat, :lng, :occupation, :studies, :popularity, :favorite_languages,
        language: []
      )
    end
    def redis
      @redis ||= Redis.new(url: ENV["REDIS_URL"])
    end
    end

