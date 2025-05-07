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
      if current_user.hidden_by_user and (params[:is_like] == true or params[:is_superlike] == true)
        render json: { status: 406, error: "No puedes estando oculto."}, status: 406
        return
      end


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
         # Abrimos thread para que se monte la conversación en twilio.
         Thread.new do
              twilio = TwilioController.new
              conversation_sid = twilio.create_conversation(current_user.id, params[:target_user])

              # Si es un sugar sweet, mandamos el primer mensaje a la conversación
              if umr.is_sugar_sweet
                 twilio.send_message_to_conversation(conversation_sid, current_user.id, params[:message])
              end

              umr.update(twilio_conversation_sid: conversation_sid)
              current_user.recalculate_ranking

              # Mandamos la push al usuario del match.
              if target_user.push_match?
                 Device.sendIndividualPush(umr.user_id,"Nuevo match"," Tienes un nuevo match en Toppin", "match", nil, "push_match")
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

          # Buscamos si existe un match_request previo
          umr = UserMatchRequest.match_between(current_user.id, params[:target_user])

          # Hay match request, pero el otro usuario lo tiene bloqueado.
          if umr and umr.is_rejected
            logger.info "Error 3"
            render json: { status: 405, error: "Match rejected error"}, status: 405
            return
          end


          if !umr # Si no lo hay, lo creamos.
             logger.info "create umr"
             umr = UserMatchRequest.create(user_id: current_user.id, is_sugar_sweet: params[:is_sugar_sweet], target_user: params[:target_user],is_like: params[:is_like], is_superlike: params[:is_superlike], user_ranking: current_user.ranking, target_user_ranking: target_user.ranking)
          else
             logger.info "update umr"
             umr.update!(is_like: params[:is_like], is_sugar_sweet: params[:is_sugar_sweet], is_superlike: params[:is_superlike], user_ranking: current_user.ranking, target_user_ranking: target_user.ranking)
          end

          logger.info "umr is now"
          logger.info umr.inspect


          # Si está dando un like y no es premium ni mujer, se lo descontamos.
          if umr.is_like and !current_user.is_premium and !umr.is_superlike and !umr.user.female?
            current_user.update(likes_left: current_user.likes_left-1, last_like_given: DateTime.now)
          end

          if umr.is_like and !umr.is_superlike
            Thread.new do
              Device.sendIndividualPush(umr.target_user,"¡Wow! Tienes nuevos admiradores :-)","Has recibido nuevos me gusta", "like", nil, "push_likes")
            end
          end

          # Si es un superlike, lo usamos y notificamos.
          if umr.is_superlike
             current_user.use_superlike
              if target_user.push_likes?
                 Device.sendIndividualPush(umr.target_user,"Nuevo super sweet"," Alguien te ha dado un super sweet en Toppin :-)", "superlike", nil, "push_likes")
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
          current_user.update(next_sugar_play: 100)
          logger.info result.inspect
        else
          current_user.update(next_sugar_play: current_user.next_sugar_play-1)
          render json: "OK2".as_json
        end
      end
  end




  # Método para deshacer un match.
  def reject_match
    
    umr = UserMatchRequest.match_between(current_user.id, params[:user_id])
    if umr
      umr.update(is_rejected: true) # Pasamos el match_request a rejected.
      
      # Nos cepillamos la conversación en twilio.
      twilio = TwilioController.new
      if umr.twilio_conversation_sid.present?
         twilio.destroy_conversation(umr.twilio_conversation_sid)
      end
      
      render json: { status: 200, error: "OK"}, status: 200
    else
      render json: { status: 405, error: "Error rejecting match"}, status: 405
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
end
