class UserMatchRequestsController < ApplicationController
  before_action :set_user_match_request, only: %i[ show edit update destroy send_first_message_to_match ]
 # skip_before_action :authenticate_user!

  # GET /user_match_requests or /user_match_requests.json
  def index
    @user_match_requests = UserMatchRequest.all
  end
  # Solicitud de match / dislike
  def send_match
      # Si estás oculto no puedes dar likes ni superlikes.
      # Comprobamos si hay alguna solicitud de match (con like) del otro usuario hacia el que lo solicita
      umr =  UserMatchRequest.match_between(params[:target_user],current_user.id)
      target_user =  User.find(params[:target_user])
      logger.info "UMR"
      logger.info umr.inspect
      # Si es superlike, vamos a ver si puede usarlo antes de nada.
      if (params[:is_superlike] === true or params[:is_sugar_sweet] === true) and current_user.superlike_available == 0 
            logger.info "Error 1"
            render json: { status: 405, error: "Error usando supersweet"}, status: 405
            return
      end
      # Si el user ya está como target de otro usuario sin ser match o superlike y le estamos dando like o superlike
      # ITS A MATCH
      if umr and umr.target_user == current_user.id and !umr.is_match and !umr.is_rejected and (params[:is_sugar_sweet] === true or params[:is_like] === true or params[:is_superlike] === true)
         logger.info umr.inspect
         umr.is_match = true
         umr.user_ranking = current_user.ranking
         umr.target_user_ranking = target_user.ranking
         umr.match_date = DateTime.now
         # Si es un superlike o sugar, lo descontamos.
         if params[:is_superlike] === true or params[:is_sugar_sweet] === true
            current_user.use_superlike
            umr.is_sugar_sweet = params[:is_sugar_sweet]
            umr.is_superlike = params[:is_superlike]
         end
         umr.save # Guardamos el match.
         # Como tenemos match, creamos conversación
         twilio = TwilioController.new
         conversation_sid = twilio.create_conversation(current_user.id, params[:target_user])
         if umr.is_sugar_sweet
           twilio.send_message_to_conversation(conversation_sid, current_user.id, params[:message])
         end
         umr.update(twilio_conversation_sid: conversation_sid)
         current_user.recalculate_ranking
         # Mandamos la push al usuario del match.
         match_user = User.find(umr.user_id)    
           devices = Device.where(user_id: match_user.id)
           notification = NotificationLocalizer.for(user: match_user, type: :match)
           devices.each do |device|
             if device.token.present?
               FirebasePushService.new.send_notification(
                 token: device.token,
                 title: notification[:title],
                 body: notification[:body],
                 data: { action: "match", user_id: umr.user_id.to_s },
                 sound: "match.mp3",
                 channel_id: "sms-channel",
                 category: "match"
               )
             end
           end
      
        
      ## SI no se cumplen las anteriores, vamos a ir viendo.
      # Es decir, el current user no tiene un swipe previo del usuario al que le está dando swipe
      else
          logger.info "NO UMR FOUND"
          # Si no te quedan likes, fuera.
          if params[:is_like] and params[:is_superlike] == false and current_user.likes_left <= 0
            time_to_likes = current_user.last_like_given+12.hours
            logger.info "Error 2"
            render json: { status: 405, error: time_to_likes.to_json }, status: 405
            return
          end
          
          # Buscar si existe un match_request previo EN CUALQUIER DIRECCIÓN
          umr = UserMatchRequest.match_between(current_user.id, params[:target_user])
          
          # Si existe un registro pero YO soy el target_user (ellos me dieron swipe primero)
          # entonces voy a ACTUALIZAR ese registro con mi respuesta
          if umr && umr.target_user == current_user.id
            logger.info "update umr (responding to their swipe)"
            # Actualizar el registro existente con mi respuesta
            umr.update!(
              is_like: params[:is_like], 
              is_rejected: params[:is_like] == false,
              user_ranking: target_user.ranking,
              target_user_ranking: current_user.ranking
            )
            
            # Notificar si el target_user tiene boost activo
            notify_boost_interaction(target_user, umr)
            # NUEVO: Notificar si YO (current_user) tengo boost activo y acabo de dar swipe
            notify_my_boost_action(current_user, target_user, umr) if current_user.high_visibility
            
          # Si existe un registro donde YO soy el user_id (yo swipeé primero)
          elsif umr && umr.user_id == current_user.id
            # Verificar si el registro está rechazado (yo lo rechacé antes)
            if umr.is_rejected
              logger.info "Error 3"
              render json: { status: 405, error: "Match rejected error"}, status: 405
              return
            end
            
            logger.info "update umr (updating my previous swipe)"
            umr.update!(
              is_like: params[:is_like], 
              is_sugar_sweet: params[:is_sugar_sweet], 
              is_superlike: params[:is_superlike], 
              user_ranking: current_user.ranking, 
              target_user_ranking: target_user.ranking,
              is_rejected: params[:is_like] == false
            )
            
            # Notificar si el target_user tiene boost activo
            notify_boost_interaction(target_user, umr)
            # NUEVO: Notificar si YO (current_user) tengo boost activo y acabo de dar swipe
            notify_my_boost_action(current_user, target_user, umr) if current_user.high_visibility
            
          else
            # No existe registro, crear uno nuevo
            logger.info "create umr"
            # Lógica para Sugar Sweet
            is_sugar_sweet = current_user.next_sugar_play == 1

            umr = UserMatchRequest.create(
              user_id: current_user.id,
              target_user: params[:target_user],
              is_like: params[:is_like],
              is_superlike: params[:is_superlike],
              user_ranking: current_user.ranking,
              target_user_ranking: target_user.ranking,
              is_sugar_sweet: is_sugar_sweet,
              is_rejected: params[:is_like] == false
            )
            
            if umr.persisted?
              # Notificar si el target_user tiene boost activo
              notify_boost_interaction(target_user, umr)
              # NUEVO: Notificar si YO (current_user) tengo boost activo y acabo de dar swipe
              notify_my_boost_action(current_user, target_user, umr) if current_user.high_visibility
            end
          end
          logger.info "umr is now"
          logger.info umr.inspect

          # Si el usuario actual está dando dislike
          if params[:is_like] == false
            umr_like = UserMatchRequest.find_by(user_id: params[:target_user], target_user: current_user.id)
            if umr_like
              umr_like.update(is_rejected: true, is_like: false)
            end
            # Notificar dislike si el target_user tiene boost activo
            notify_boost_interaction(target_user, umr)
          end
          # Si está dando un like y no es premium ni mujer, se lo descontamos.
          if umr.is_like and !current_user.is_premium and !umr.is_superlike and !umr.user.female?
            current_user.update(likes_left: current_user.likes_left-1, last_like_given: DateTime.now)
          end
          
          if umr.is_like and !umr.is_superlike
            target_user = User.find(umr.target_user)
            devices = Device.where(user_id: target_user.id)
            notification = NotificationLocalizer.for(user: target_user, type: :like)
            devices.each do |device|
              if device.token.present?
                FirebasePushService.new.send_notification(
                  token: device.token,
                  title: notification[:title],
                  body: notification[:body],
                  data: { action: "match", user_id: umr.user_id.to_s },
                  #sound: "match.mp3",
                  channel_id: "sms-channel"
                )
              end
            end
          end
          # Si es un superlike, lo usamos y notificamos.
          if umr.is_superlike
             current_user.use_superlike
              target_user = User.find(umr.target_user)
              devices = Device.where(user_id: target_user.id)
              notification = NotificationLocalizer.for(user: umr.user, type: :super_like)
              if target_user.push_likes?
                 #Device.sendIndividualPush(umr.target_user,"Nuevo super sweet"," Alguien te ha dado un super sweet en Toppin :-)", "superlike", nil, "push_likes")
              devices.each do |device|
              if device.token.present?
                FirebasePushService.new.send_notification(
                  token: device.token,
                  title: notification[:title],
                  body: notification[:body],
                  data: { action: "like", user_id: umr.user_id.to_s }
                )
              end
            end
              end
          end
          # Si es un superlike, lo usamos y notificamos.
          if umr.is_sugar_sweet
            logger.info "IS SUGAR SWEET"
             current_user.use_superlike
             umr.update(match_date: DateTime.now)
               Thread.new do
                    twilio = TwilioController.new
                    conversation_sid = twilio.create_conversation(current_user.id, params[:target_user])
                    twilio.send_message_to_conversation(conversation_sid, current_user.id, params[:message])
                    umr.update(twilio_conversation_sid: conversation_sid)
                    logger.info "IS SUGAR SWEET TWILIO IS "+conversation_sid.to_s
                    # Mandamos la push al usuario del match.
                    if target_user.push_match?
                       Device.sendIndividualPush(umr.target_user,"¡Wow! ¡Te han dado un Sugar Sweet!", params[:message], "sugar_sweet", nil, "push_likes")
                    end
                end # thread
          end # sugar
      end
      if umr.is_match # Si es un match, renderizamos la vista show, porque en jbuilder tenemos los datos de los usuarios.
        @user_match_request = umr
        render 'show'
        
      else
        # Nos toca sugarplay
        if current_user.next_sugar_play == 0
          umr = current_user.incoming_likes
          # Si tenemos algún like
          if umr.any?
              umr = umr.shuffle
              result = {
                sugar_play: umr.first.user_id 
              }
              render json: result.to_json
          else
            render json: "OK1".as_json
          end
          current_user.update(next_sugar_play: 120)
          logger.info result.inspect
        else
          current_user.update(next_sugar_play: current_user.next_sugar_play-1)
          render json: "OK2".as_json
        end
      end
  end


  def reject_match
    target_user_id = params[:user_id] || params[:target_user_id]

    umr = UserMatchRequest.find_by(user_id: target_user_id, target_user: current_user.id)

    if umr
      umr.update(is_rejected: true)
      # Eliminamos la conversación en Twilio si existe
      if umr.twilio_conversation_sid.present?
        TwilioController.new.destroy_conversation(umr.twilio_conversation_sid)
      end
      render json: { status: 200, error: "OK" }, status: 200
    else
      # Si no existe, lo creamos como rechazado
      umr = UserMatchRequest.create(
        user_id: target_user_id,
        target_user: current_user.id,
        is_like: false,
        is_rejected: true
      )
      if umr.persisted?
        render json: { status: 200, error: "OK" }, status: 200
      else
        render json: { status: 405, error: "Error rejecting match" }, status: 405
      end
    end
  end

  # API endpoint para enviar un mensaje de chat a un match. (Se usa nada mas hacer el match para mandar el primer mensaje).
  def send_first_message_to_match
    conversation_sid = @user_match_request.twilio_conversation_sid
    if conversation_sid
      twilio = TwilioController.new
      message = twilio.send_message_to_conversation(conversation_sid, current_user.id, params[:message])
      logger.info "MENSAJE"+message.inspect
    else
      # KO
    end
    render json: "OK".to_json
  end
  # Este endpoint envía un mensaje a tu superlike y lo convierte en un match.
  def send_first_message_to_superlike
    umr = UserMatchRequest.find_by(id: params[:id])
    if umr
      target_user = umr.target
      # Generamos en match
      umr.is_match = true
      umr.user_ranking = current_user.ranking
      umr.target_user_ranking = umr.target.ranking
      umr.match_date = DateTime.now
      umr.save
      twilio = TwilioController.new
      conversation_sid = twilio.create_conversation(current_user.id, umr.user_id)
      if conversation_sid
        render json: conversation_sid.to_json
            # Generamos la conversación y enviamos el primer mensaje
            Thread.new do
                # Enviamos el primer mensaje
                twilio.send_message_to_conversation(conversation_sid, current_user.id, params[:message])
                umr.update(twilio_conversation_sid: conversation_sid)
                current_user.recalculate_ranking
                # Mandamos la push al usuario del match.
                if umr.user.push_match?
                    Device.sendIndividualPush(umr.user_id,"Nuevo match"," ¡Tu supersweet ha dado resultado!", "match", nil, "push_match")
                end
            end
      end
    else
      render json: { status: 400, error: "Error sending message"}, status: 400
    end
  end
  # Devuelve todos los matches de un usuario.
  def get_user_matches
    logger.info "GET_USER_MATCHES_FIRED"
    @user_match_requests = current_user.matches
    #target_user_ids = @user_match_requests.pluck(:target_user)
    #@target_users = User.where(id: target_user_ids).to_a
    #logger.info "get user matches"+@user_match_requests.inspect
    render 'index'
  end
  # Devuelve usuarios a los que les gustas, pero tú no les has dado like de momento.
  def get_user_likes
    @user_match_requests = UserMatchRequest.where(target_user: current_user.id, is_match: false, is_like: true, is_rejected: false).order(id: :desc).limit(99)
    render 'index'
  end
  # Devuelve usuarios a los que has dado o te han dado un superlike
  def get_user_superlikes
    @user_match_requests = current_user.given_received_requests.where(is_match: false, is_superlike: true, is_rejected: false).order(id: :desc)
    render 'index'
  end
  # GET /user_match_requests/1 or /user_match_requests/1.json
  def show
   # @user_match_request = current_user.user_match_request
  end
  # GET /user_match_requests/new
  def new
    @user_match_request = UserMatchRequest.new
  end
  # GET /user_match_requests/1/edit
  def edit
  end
  # POST /user_match_requests or /user_match_requests.json
  def create
    @user_match_request = UserMatchRequest.new(user_match_request_params)
    respond_to do |format|
      if @user_match_request.save
        format.html { redirect_to @user_match_request, notice: "User match request was successfully created." }
        format.json { render :show, status: :created, location: @user_match_request }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_match_request.errors, status: :unprocessable_entity }
      end
    end
  end
  # PATCH/PUT /user_match_requests/1 or /user_match_requests/1.json
  def update
    respond_to do |format|
      if @user_match_request.update(user_match_request_params)
        format.html { redirect_to @user_match_request, notice: "User match request was successfully updated." }
        format.json { render :show, status: :ok, location: @user_match_request }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_match_request.errors, status: :unprocessable_entity }
      end
    end
  end
  # DELETE /user_match_requests/1 or /user_match_requests/1.json
  def destroy
    @user_match_request.destroy
    respond_to do |format|
      format.html { redirect_to user_match_requests_url, notice: "User match request was successfully destroyed." }
      format.json { head :no_content }
    end
  end
  def current_user_requests
    render json: current_user.user_match_requests
  end
  # Return registries where target user is current user
  # Conditions: no match or rejected are satisfied
  def current_user_likes
    current_user_id = params[:id]
    user_likes = UserMatchRequest.where(target_user: current_user_id, is_match: false, is_rejected: false)
    render json: user_likes
  end
  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_match_request
      @user_match_request = UserMatchRequest.find(params[:id])
    end
    # Only allow a list of trusted parameters through.
    def user_match_request_params
      params.require(:user_match_request).permit(:user_id, :target_user, :is_match, :is_paid, :is_rejected, :affinity_index)
    end

    # Notifica en tiempo real si el target_user tiene un boost activo
    def notify_boost_interaction(target_user, umr)
      return unless target_user.high_visibility && target_user.high_visibility_expire
      
      # Verificar que la interacción ocurrió durante el boost activo
      boost_start = target_user.last_boost_started_at
      return unless boost_start && umr.created_at >= boost_start
      
      # Obtener todas las interacciones del boost actual (INCLUYENDO matches)
      boost_end_time = target_user.high_visibility_expire
      all_interactions = UserMatchRequest.where(target_user: target_user.id)
                                         .where("created_at >= ? AND created_at <= ?", boost_start, boost_end_time)
                                         .order(created_at: :desc)
      
      # Obtener los IDs de usuarios que han interactuado
      user_ids = all_interactions.pluck(:user_id).uniq
      
      # Cargar usuarios con todas sus relaciones (igual que en user_swipes y boost_interactions)
      users = User.includes(:user_info_item_values, :user_interests, :user_media, :user_main_interests, :tmdb_user_data, :tmdb_user_series_data)
                  .where(id: user_ids)
      
      # Construir array con información de cada interacción
      interactions_data = all_interactions.map do |interaction|
        user = users.find { |u| u.id == interaction.user_id }
        next unless user
        
        # Determinar el tipo de interacción que ELLOS hicieron hacia MÍ (el que tiene boost)
        their_action = if interaction.is_match
                         "match"
                       elsif interaction.is_rejected
                         "dislike"
                       elsif interaction.is_like
                         "like"
                       else
                         "dislike"
                       end
        
      # Buscar si YO (el que tiene boost) también tengo una interacción hacia ELLOS
      # Buscar en AMBAS direcciones porque el registro puede estar invertido
      my_interaction = UserMatchRequest.where(
        "(user_id = ? AND target_user = ?) OR (user_id = ? AND target_user = ?)",
        target_user.id, user.id, user.id, target_user.id
      ).order(updated_at: :desc).first
      
      # Determinar MI acción hacia ELLOS
      my_action = if interaction.is_match
                    "match"
                  elsif my_interaction
                    # Si el registro es el MISMO que la interacción recibida
                    if my_interaction.id == interaction.id
                      # Mi respuesta está en la actualización de este registro
                      if my_interaction.is_match
                        "match"
                      elsif my_interaction.created_at != my_interaction.updated_at
                        # Respondí
                        if my_interaction.is_rejected == true || my_interaction.is_like == false
                          "dislike"
                        elsif my_interaction.is_like == true
                          "like"
                        else
                          "none"
                        end
                      else
                        "none"
                      end
                    elsif my_interaction.user_id == target_user.id
                      # YO creé un registro separado
                      if my_interaction.is_like == true
                        "like"
                      elsif my_interaction.is_rejected == true || my_interaction.is_like == false
                        "dislike"
                      else
                        "none"
                      end
                    else
                      "none"
                    end
                  else
                    "none"  # No he interactuado con esta persona aún
                  end
        
        {
          interaction_type: their_action,  # Lo que ELLOS me hicieron
          my_action: my_action,            # Lo que YO les hice (o "none")
          interaction_time: interaction.created_at,
          user: user.as_json(
            methods: [:user_age, :user_media_url],
            include: [
              :user_media,
              :user_interests,
              :user_info_item_values,
              :user_main_interests,
              :tmdb_user_data,
              :tmdb_user_series_data
            ]
          )
        }
      end.compact
      
      # Determinar el tipo de la última interacción que ELLOS hicieron
      latest_their_action = if umr.is_match
                              "match"
                            elsif umr.is_rejected
                              "dislike"
                            elsif umr.is_like
                              "like"
                            else
                              "dislike"
                            end
      
      # Buscar si YO (el que tiene boost) ya respondí al current_user
      # Buscar en AMBAS direcciones
      my_response = UserMatchRequest.where(
        "(user_id = ? AND target_user = ?) OR (user_id = ? AND target_user = ?)",
        target_user.id, current_user.id, current_user.id, target_user.id
      ).order(updated_at: :desc).first
      
      latest_my_action = if umr.is_match
                           "match"
                         elsif my_response
                           # Si el registro es el MISMO que umr (la interacción recibida)
                           if my_response.id == umr.id
                             # Mi respuesta está en la actualización
                             if my_response.is_match
                               "match"
                             elsif my_response.created_at != my_response.updated_at
                               # Respondí
                               if my_response.is_rejected == true || my_response.is_like == false
                                 "dislike"
                               elsif my_response.is_like == true
                                 "like"
                               else
                                 "none"
                               end
                             else
                               "none"
                             end
                           elsif my_response.user_id == target_user.id
                             # YO creé un registro separado
                             if my_response.is_like == true
                               "like"
                             elsif my_response.is_rejected == true || my_response.is_like == false
                               "dislike"
                             else
                               "none"
                             end
                           else
                             "none"
                           end
                         else
                           "none"
                         end
      
      # Preparar el payload para el websocket
      websocket_payload = {
        type: "boost_interactions_update",
        boost_started_at: boost_start,
        boost_expires_at: boost_end_time,
        interactions_count: interactions_data.length,
        interactions: interactions_data,
        latest_interaction: {
          interaction_type: latest_their_action,  # Lo que ELLOS me hicieron
          my_action: latest_my_action,            # Lo que YO les hice (o "none")
          interaction_time: umr.created_at,
          user: current_user.as_json(
            methods: [:user_age, :user_media_url],
            include: [
              :user_media,
              :user_interests,
              :user_info_item_values,
              :user_main_interests,
              :tmdb_user_data,
              :tmdb_user_series_data
            ]
          )
        }
      }
      
      # LOG DETALLADO DEL WEBSOCKET
      Rails.logger.info "=" * 80
      Rails.logger.info "[BoostInteraction WebSocket] ALGUIEN me dio swipe durante MI boost"
      Rails.logger.info "Usuario con boost (YO): #{target_user.id} (#{target_user.name})"
      Rails.logger.info "Usuario que me dio swipe: #{current_user.id} (#{current_user.name})"
      Rails.logger.info "Tipo de interacción RECIBIDA: #{latest_their_action}"
      Rails.logger.info "Mi acción PREVIA hacia ellos: #{latest_my_action}"
      Rails.logger.info "Total de interacciones en mi boost: #{interactions_data.length}"
      Rails.logger.info "Payload completo del websocket:"
      Rails.logger.info JSON.pretty_generate(websocket_payload.as_json)
      Rails.logger.info "=" * 80
      
      # Enviar la lista completa actualizada a través de AliveChannel AL USUARIO CON BOOST
      AliveChannel.broadcast_to(target_user, websocket_payload)
    end
    
    # Notifica cuando YO (con boost activo) doy swipe a alguien
    def notify_my_boost_action(me_with_boost, person_i_swiped, umr)
      return unless me_with_boost.high_visibility && me_with_boost.high_visibility_expire
      
      # Verificar que mi boost está activo
      boost_start = me_with_boost.last_boost_started_at
      return unless boost_start
      
      boost_end_time = me_with_boost.high_visibility_expire
      
      # 1. Interacciones donde OTROS me swipearon durante mi boost
      incoming_interactions = UserMatchRequest.where(target_user: me_with_boost.id)
                                              .where("created_at >= ? AND created_at <= ?", boost_start, boost_end_time)
      
      # 2. Interacciones donde YO swipeé a OTROS durante mi boost
      outgoing_interactions = UserMatchRequest.where(user_id: me_with_boost.id)
                                              .where("created_at >= ? AND created_at <= ?", boost_start, boost_end_time)
      
      # Combinar ambos conjuntos de usuarios (sin duplicados)
      incoming_user_ids = incoming_interactions.pluck(:user_id).uniq
      outgoing_user_ids = outgoing_interactions.pluck(:target_user).uniq
      all_user_ids = (incoming_user_ids + outgoing_user_ids).uniq
      
      # Cargar todos los usuarios con sus relaciones
      users = User.includes(:user_info_item_values, :user_interests, :user_media, :user_main_interests, :tmdb_user_data, :tmdb_user_series_data)
                  .where(id: all_user_ids)
      
      # Construir array con información de cada interacción
      interactions_data = all_user_ids.map do |user_id|
        user = users.find { |u| u.id == user_id }
        next unless user
        
        # Buscar si ELLOS me swipearon
        their_interaction = incoming_interactions.find { |i| i.user_id == user_id }
        
        # Lo que ELLOS me hicieron
        their_action = if their_interaction
                         if their_interaction.is_match
                           "match"
                         elsif their_interaction.is_like == true
                           "like"
                         elsif their_interaction.is_rejected == true || their_interaction.is_like == false
                           "dislike"
                         else
                           "none"
                         end
                       else
                         "none"  # No me han swipeado
                       end
        
        # Buscar MI interacción hacia ELLOS
        # Puede estar en cualquier dirección porque cuando respondes a un swipe,
        # se actualiza el registro original en lugar de crear uno nuevo
        my_interaction = UserMatchRequest.where(
          "(user_id = ? AND target_user = ?) OR (user_id = ? AND target_user = ?)",
          me_with_boost.id, user_id, user_id, me_with_boost.id
        ).order(updated_at: :desc).first
        
        # Lo que YO les hice
        # Necesitamos determinar si existe una interacción mía hacia ellos
        my_action = if their_interaction&.is_match
                      "match"
                    elsif my_interaction
                      # Si el registro es their_interaction (ellos me swipearon durante el boost)
                      # entonces mi acción está en la actualización de ese registro
                      if my_interaction.id == their_interaction&.id
                        # Es el MISMO registro - mi respuesta está en la actualización
                        if my_interaction.is_match
                          "match"
                        elsif my_interaction.created_at != my_interaction.updated_at
                          # El registro fue actualizado = respondí
                          if my_interaction.is_rejected == true || my_interaction.is_like == false
                            "dislike"
                          elsif my_interaction.is_like == true
                            "like"
                          else
                            "none"
                          end
                        else
                          "none"  # No he respondido
                        end
                      elsif my_interaction.user_id == me_with_boost.id
                        # YO creé un registro separado hacia ellos
                        if my_interaction.is_like == true
                          "like"
                        elsif my_interaction.is_rejected == true || my_interaction.is_like == false
                          "dislike"
                        else
                          "none"
                        end
                      else
                        "none"
                      end
                    else
                      "none"  # No existe interacción
                    end
        
        # Usar la fecha de la interacción más reciente
        interaction_time = [their_interaction&.created_at, my_interaction&.created_at].compact.max
        
        {
          interaction_type: their_action,
          my_action: my_action,
          interaction_time: interaction_time,
          user: user.as_json(
            methods: [:user_age, :user_media_url],
            include: [
              :user_media,
              :user_interests,
              :user_info_item_values,
              :user_main_interests,
              :tmdb_user_data,
              :tmdb_user_series_data
            ]
          )
        }
      end.compact.sort_by { |i| i[:interaction_time] }.reverse
      
      # Verificar si la persona a la que le di swipe me había dado swipe antes durante mi boost
      their_previous_interaction = incoming_interactions.find { |i| i.user_id == person_i_swiped.id }
      
      # Determinar si esta es una respuesta a una interacción previa
      is_response_to_their_swipe = their_previous_interaction.present?
      
      # Preparar el payload
      websocket_payload = {
        type: "boost_interactions_update",
        boost_started_at: boost_start,
        boost_expires_at: boost_end_time,
        interactions_count: interactions_data.length,
        interactions: interactions_data,
        latest_interaction: {
          is_my_response: is_response_to_their_swipe,  # TRUE si estoy respondiendo a su swipe
          my_action: umr.is_like ? "like" : "dislike",  # Lo que YO acabo de hacer
          interaction_time: umr.created_at,
          user: person_i_swiped.as_json(
            methods: [:user_age, :user_media_url],
            include: [
              :user_media,
              :user_interests,
              :user_info_item_values,
              :user_main_interests,
              :tmdb_user_data,
              :tmdb_user_series_data
            ]
          )
        }
      }
      
      # LOG DETALLADO
      Rails.logger.info "=" * 80
      Rails.logger.info "[MyBoostAction WebSocket] YO DI SWIPE durante MI boost"
      Rails.logger.info "YO (con boost): #{me_with_boost.id} (#{me_with_boost.name})"
      Rails.logger.info "A QUIEN le di swipe: #{person_i_swiped.id} (#{person_i_swiped.name})"
      Rails.logger.info "MI acción: #{umr.is_like ? 'like' : 'dislike'}"
      Rails.logger.info "¿Es respuesta a su swipe?: #{is_response_to_their_swipe}"
      if their_previous_interaction
        their_action_type = their_previous_interaction.is_match ? 'match' : (their_previous_interaction.is_like ? 'like' : 'dislike')
        Rails.logger.info "SU interacción previa hacia mí: #{their_action_type} (#{their_previous_interaction.created_at})"
      end
      Rails.logger.info "Total de interacciones en mi boost: #{interactions_data.length}"
      Rails.logger.info "Payload completo del websocket:"
      Rails.logger.info JSON.pretty_generate(websocket_payload.as_json)
      Rails.logger.info "=" * 80
      
      # Enviar a MÍ MISMO (quien tiene el boost y acaba de dar swipe)
      AliveChannel.broadcast_to(me_with_boost, websocket_payload)
    end
end
