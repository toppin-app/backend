class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :destroy, :block]
  before_action :check_admin, only: [:index, :new, :edit, :create_match, :create_like]
  skip_before_action :verify_authenticity_token, :only => [:show, :edit, :update, :destroy, :block]
  skip_before_action :authenticate_user!, :only => [:reset_password_sent, :password_changed, :cron_recalculate_popularity, :cron_check_outdated_boosts, :cron_regenerate_superlike, :cron_regenerate_likes, :social_login_check, :cron_randomize_bundled_users_geolocation]

  CRON_TOKEN = "8b645d9b-2679-4a9d-a295-faa88e9dca8c".freeze


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
  end


  def get_user
     @user = User.find(params[:id])
     render 'show'
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

    if params[:user][:password].blank?
      params[:user].delete :password
      params[:user].delete :password_confirmation
    end


    if params[:id]
      @user = User.find(params[:id])
    else
     @user = User.find(params[:user][:id])
    end


    respond_to do |format|

      if @user.update(user_params)

        if params[:user][:images]
            params[:user][:images].each do |image|
              photo = UserMedium.create(file: image, user_id: @user.id)
              photo.save
            end
        end

        if params[:info_item_values]
          params[:info_item_values].each do |iv|
              if !iv.blank?
                @user.user_info_item_values.create(info_item_value_id: iv)
              end
          end
        end

        if params[:distance_range]
            @user.user_filter_preference&.update(distance_range: params[:distance_range])
        end

        if params[:filter_gender]
          @user.user_filter_preference&.update(gender_preferences: params[:filter_gender])
        end

        if params[:user_interests]
          params[:user_interests].each do |iv|
              if !iv.blank?
                @user.user_interests.create(interest_id: iv)
              end
          end
        end

        if params[:user_main_interests]
          user_main_interests_controller = UserMainInterestsController.new
          user_main_interests_controller.bulk_create(user_main_interests: params[:user_main_interests])
        end

        format.html { redirect_to show_user_path(id: @user.id), notice: 'User was successfully updated.' }
        format.json { render 'show'}
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


  # Elimina la cuenta de un usuario.
  def delete_account
      current_user.destroy
      render json: { status: 200, error: "User deleted"}, status: 200
  end


  # Hace manualmente un match entre dos usuarios. (desde el admin)
  def create_match
    umr = UserMatchRequest.find(params[:id])
    umr.update(is_match: true, match_date: DateTime.now, user_ranking: umr.user.ranking, target_user_ranking: umr.target.ranking)

    twilio = TwilioController.new
    conversation_sid = twilio.create_conversation(umr.user_id, umr.target_user)
    umr.update(twilio_conversation_sid: conversation_sid)
    redirect_to show_user_path(id: umr.target_user), notice: 'Match generado con éxito.'
  end


  # Hacer manualmente like entre dos users (desde el admin)
  def create_like
    umr = UserMatchRequest.find_by(user_id: params[:user_id], target_user: params[:target_user])
    if !umr
       umr = UserMatchRequest.create(user_id: params[:user_id], target_user: params[:target_user], is_like: true, is_rejected: false, is_superlike: false)
    end


    Thread.new do
      Device.sendIndividualPush(umr.target_user,"¡Wow! Tienes nuevos admiradores :-)","Has recibido nuevos me gusta", "like", nil, "push_likes")
    end

    redirect_to show_user_path(id: umr.user_id), notice: 'Like generado con éxito.'
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
    User.where(superlike_available: 0, current_subscription_name: nil).where("last_superlike_given <= ?", DateTime.now-7.days).update_all(superlike_available:1)
    User.where(superlike_available: 0).where.not(current_subscription_name: nil).where("last_superlike_given <= ?", DateTime.now-7.days).update_all(superlike_available:5)

    # Revisamos los usuarios que llevan más de 10 minutos sin actividad para quitarles el online (is_connected)
      User.where(last_connection: false).update(is_connected: false)
      User.where(last_connection: DateTime.now-100.years..DateTime.now-10.minutes).update(is_connected: false)
    # fin de revisión de online

    render json: "OK".to_json
  end



  # Método cron para quitar el high_visibility a aquellos usuarios que lo tengan caducado.
  def cron_check_outdated_boosts
    users = User.where(high_visibility: true).where("high_visibility_expire <= ?", DateTime.now)

    users.each do |user|
      user.update(high_visibility: false)
      Device.sendIndividualPush(user.id,"Tu power sweet ha finalizado", "", "boost_ended")
    end

    render json: "OK".to_json
  end


  # Método cron para que te devuelva los likes cada 12h.
  def cron_regenerate_likes
    users = User.where("last_like_given <= ?", DateTime.now-12.hours)

    users.each do |user|
        if user.likes_left == 0
           Device.sendIndividualPush(user.id,"¡Ya puedes empezar a toppitear de nuevo!", "", "likes_regenerated")
        end
       user.update(likes_left: 55)
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



  def toggle_visibility
      current_user.toggle :hidden_by_user
      current_user.save

      render json: { status: 200, message: current_user.hidden_by_user }, status: 200
  end


  # Desactivar publi, solo usuarios premium
  def toggle_publi
    if current_user.is_premium
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
    user_ids = UserFilterPreference.where(
      "((gender_preferences = ? OR gender_preferences LIKE ? OR gender_preferences LIKE ? OR gender_preferences LIKE ?) OR gender_preferences LIKE ?) AND user_id != ?",
      my_gender,
      "#{my_gender},%",
      "%,#{my_gender}",
      "%,#{my_gender},%",
      "gender_any",
      current_user_id
    ).pluck(:user_id)

    users = User.where(id: user_ids)
    puts("------------------")
    puts("------------------")
    puts("------------------ 1 ")
    puts(users)
    puts("##################")
    puts("##################")
    puts("##################")
    ##

    if filter_preference.gender_preferences.present? and !filter_preference.gender_any?
       users = users.active.visible.near([current_user.lat, current_user.lng], filter_preference.distance_range, order: 'id').where(gender: filter_preference.gender)
    else
       users = users.active.visible.near([current_user.lat, current_user.lng], filter_preference.distance_range, order: 'id')
    end
    puts("------------------")
    puts("------------------")
    puts("------------------ 2 ")
    puts(users)
    puts("##################")
    puts("##################")
    puts("##################")
    


    logger.info "USERS0"
   # logger.info users.inspect

    rejected = UserMatchRequest.rejected(current_user_id)
    rejected_users = rejected.pluck(:user_id) + rejected.pluck(:target_user)



    matches = current_user.matches
    matched_users = matches.pluck(:user_id) +  matches.pluck(:target_user)

    rejected_users = rejected_users + matched_users
    rejected_users = rejected_users.uniq


    logger.info "REJECTED::"+rejected_users.inspect

    users = users.where.not(id: rejected_users)
    puts("------------------")
    puts("------------------")
    puts("------------------ 3 ")
    puts(users)
    puts(start_date)
    puts(end_date)
    puts("##################")
    puts("##################")
    puts("##################")

    # Edad
    if filter_preference.age_from.present? and filter_preference.age_till.present?
       users = users.born_between(start_date, end_date)
    end

    puts("------------------")
    puts("------------------")
    puts("------------------ 4 ")
    puts(users)
    puts("##################")
    puts("##################")
    puts("##################")

    # Filtro usuarios verificados
    if filter_preference.only_verified_users
        users = users.where(verified: true)
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
          UserInterest.where(interest_id: interests, user_id: user_ids).pluck(:user_id).each do |id|
            user_with_interests << id
          end
        end

    end


    # Categorías
    if filter_preference.categories.present?

        categories = JSON.parse filter_preference.categories
        categories = categories["categories"]

       if categories.any?
          UserInfoItemValue.where(info_item_value_id: categories, user_id: user_ids).pluck(:user_id).each do |id|
           user_with_interests << id
          end
       end

    end


    if user_with_interests.any?
       user_with_interests = user_with_interests.uniq
       user_ids = user_with_interests
    end


    logger.info "IDS 2"
    logger.info user_ids.inspect


    users = User.where(id: user_ids)

    users_with_boost = users.where(high_visibility: true).pluck(:id).shuffle
    users_without_boost = users.where(high_visibility: false).pluck(:id).shuffle


    # Añadimos los likes al principio, para ello los extraemos
    incoming_likes = current_user.incoming_likes.pluck(:user_id)


    if incoming_likes.count > 1
        # mezclamos y eliminamos uno para el sugar play
          incoming_likes = incoming_likes.shuffle
          incoming_likes.shift
        #
    end


    user_ids = users_with_boost+users_without_boost


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


    @users = User.includes(:user_info_item_values, :user_interests, :user_media).where(id: user_ids).where.not(id: discarded_users).where.not(id: current_user_id).sort_by {|m| user_ids.index(m.id)}

    if !@users.any? or @users.count < 30
      @users = User.includes(:user_info_item_values, :user_interests, :user_media).where(id: user_ids).where.not(id: current_user_id).sort_by {|m| user_ids.index(m.id)}
    end




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

    if current_user.show_publi
       @publis = Publi.active_now
    else
      @publis = []
    end


   # render 'index'
    # render json: @users.as_json(methods: [:user_age, :user_media_url], :include => [:user_media])
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
     user_ids = UserFilterPreference.where(gender_preferences: [my_gender, "gender_any"]).pluck(:user_id)


     # Filtro por lo que busca mi usuario. Si le da igual, saco todos los users (filtrados arriba)
     if my_gender_preference == "gender_any"
        users = User.where(id: user_ids)

     else
      logger.info "GENDER PREFERENCE "+my_gender_preference
      # Si tiene preferencia de genero, busco solo usuarios de ese genero.
      users = User.where(id: user_ids, gender: my_gender_preference)
     end


    @users = users.visible.where.not(id: to_remove).order(ratio_likes: :desc).limit(12)


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

=begin
      pond = {
        "donut"  => 90,
        "heart" => 5,
        "muffin"  => 85,
        "card" => 5,
        "star" => 5,
        "bear" => 85,
        "battery" => 10
      }
=end
      if current_user.spin_roulette_available == 0
            render json: { status: 405, message: "No te quedan tiradas"}, status: 405
           return
      end

      # # Si es tu primera tirada, 100% star, que significa que te toca un superlike.
      # if current_user.last_roulette_played.nil?
      #   pond = {
      #     "donut"  => 0,
      #     "heart" => 0,
      #     "muffin"  => 0,
      #     "card" => 0,
      #     "star" => 100,
      #     "bear" => 0,
      #     "battery" => 0
      #   }
      # else
      #   if current_user.incoming_likes.count > 0 # Si tiene algún me gusta, usamos el pond normal.
      #       pond = {
      #         "donut"  => 90,
      #         "heart" => 5,
      #         "muffin"  => 85,
      #         "card" => 5,
      #         "star" => 5,
      #         "bear" => 85,
      #         "battery" => 10
      #       }
      #   else # No tiene ningún me gusta, así que le daremos un boost
      #       pond = {
      #         "donut"  => 14,
      #         "heart" => 14,
      #         "muffin"  => 14,
      #         "card" => 14,
      #         "star" => 14,
      #         "bear" => 14,
      #         "battery" => 16
      #       }
      #   end
      # end

      pond = {
          "donut"  => 14,
              "heart" => 14,
              "muffin"  => 14,
              "card" => 14,
              "star" => 14,
              "bear" => 14,
              "battery" => 16
      }

      available = current_user.spin_roulette_available-1
      current_user.update(last_roulette_played: DateTime.now, spin_roulette_available: available)


      pickup = Pickup.new(pond)
      result = pickup.pick(1)


        if result == "star"
          current_user.increase_consumable("superlikes",1)
        end

        if result == "battery"
          current_user.increase_consumable("boosters",1)
        end

        if result == "heart"
          current_user.increase_consumable("likes",10)
        end


      render json: result.to_json

  end


  def validate_image

    current_user.update!(verification_image: params[:data][:verification_image])

    credentials = Aws::Credentials.new(
       "AKIARM4ZEEKGJIZ2HKUZ",
       "6PH1iXAB6NuD9710p3nsX0cdJxFVsUkBOYBe8HUE",
    )

      client = Aws::Rekognition::Client.new(
        region: "eu-west-1",
        credentials: credentials,
      )

      img = open("https://www.transfer-lesvos.com/wp-content/uploads/2017/09/MidiBus_1.jpg")
      img = Base64.strict_encode64(img.read)
      data_url = "data:image/jpeg;base64," + img
      #raise data_url.inspect

      #raise img.inspect
=begin
      resp = client.detect_moderation_labels(
         image: { bytes: User.find(59).user_media.last.file.read },
         min_confidence: 1.0,
          human_loop_config: {
            human_loop_name: "tuxone009125", # required
            flow_definition_arn: "FlowDefinitionArn", # required
            data_attributes: {
              content_classifiers: ["FreeOfPersonallyIdentifiableInformation"], # accepts FreeOfPersonallyIdentifiableInformation, FreeOfAdultContent
            },
          },
       )
=end

     resp = client.detect_labels(


     image: { bytes: current_user.verification_image.file.read })
     #image: { bytes: User.find(59).verification_image.file.read })

      finger = resp.labels.select { |favor| favor.name == "Finger" and favor.confidence > 50 }
  #    face = resp.labels.select { |favor| favor.name == "Face" and favor.confidence > 50 }
      person = resp.labels.select { |favor| favor.name == "Person" and favor.confidence > 60 }


      if finger.any? and person.any?
        current_user.update(verified: true)
        render json: { status: 200, message: "OK"}, status: 200
      else
        logger.info resp.labels.inspect
        render json: { status: 400, message: "KO"}, status: 400
      end

     # render json: result.to_json


  end


  def detect_nudity

    credentials = Aws::Credentials.new(
       "AKIARM4ZEEKGJIZ2HKUZ",
       "6PH1iXAB6NuD9710p3nsX0cdJxFVsUkBOYBe8HUE",
    )

      client = Aws::Rekognition::Client.new(
        region: "eu-west-1",
        credentials: credentials,
      )

        resp = client.detect_moderation_labels({
          image: { bytes: User.find(69).user_media.last.file.read },
          min_confidence: 1.0
        })

        #  image: { # required
            #s3_object: {
            #  bucket: "toppin",
            #  name: "141838-topless.jpg",
           #   version: "S3ObjectVersion",
         #   },
          #},
      #  render json: resp.moderation_labels

       # return

        nude = resp.moderation_labels.select { |favor| favor.name == "Explicit Nudity" and favor.confidence > 50 }

      if !nude.any?
        render json: { status: 200, message: "OK"}, status: 200
      else
        render json: { status: 400, nudity: nude, message: "KO"}, status: 400
      end

       # raise resp.moderation_labels.inspect


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

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_params
      params.require(:user).permit(:email, :name, :password, :password_confirmation, :user_name, :blocked, :current_subscription_id, :show_publi, :current_subscription_name, :verified, :verification_file, :push_token, :device_id, :device_platform, :description, :gender, :high_visibility, :hidden_by_user, :is_connected, :last_connection, :last_match, :is_new, :activity_level, :birthday, :born_in, :living_in, :locality, :country, :lat, :lng, :occupation, :studies, :popularity, user_media:[:id, :file, :position])
    end
end
