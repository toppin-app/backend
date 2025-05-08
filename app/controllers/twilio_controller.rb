class TwilioController < ApplicationController

	skip_before_action :authenticate_user!, :only => [:twilio_webhook]
	before_action :set_account



	#
	def twilio_webhook

	Thread.new do
		set_account


		message = @client.conversations
        .conversations(params[:ChannelSid]).fetch


        			logger.info message.inspect


              unique_name =  message.unique_name.split("@")
              sender = params[:ClientIdentity]


              if unique_name[0] == sender
              	 receiver = unique_name[1]
              else
              	receiver = unique_name[0]
              end



         receiver = User.find(receiver.to_i)

         if !receiver.push_chat
         	render json: "OK".to_json
         	return
         end


		 # Si el usuario está actualmente dentro de la conversación, no le mandamos la push.
		 if receiver.current_conversation == params[:ChannelSid]
			render json: "OK".to_json
			return
		end


         sender = User.find(params[:ClientIdentity].to_i)


         logger.info "RECEPTOR: "+receiver.inspect

		 umr = UserMatchRequest.find_by(twilio_conversation_sid: params[:ChannelSid])

		 logger.info "UMR FOUND:: "+umr.inspect
		 if umr
			if !umr.is_match
				umr.update(is_match: true, match_date: DateTime.now) 
			end
		 end




		 Thread.new do
	         #  Device.sendIndividualPush(receiver.id, sender.name+" te ha enviado un mensaje nuevo","Te está eperando en Toppin", nil, nil)
			 Device.sendIndividualPush(receiver.id, nil,"Has recibido un mensaje nuevo de "+sender.name, nil, nil, "push_chat")    
		  end

	      

      end

      render json: "OK".to_json


	end


	# Genera un token de acceso a twilio para usar desde el front
	def generate_access_token

	    	set_account


			identity = current_user.id

			# Create Chat grant for our token
			grant = Twilio::JWT::AccessToken::ChatGrant.new

			grant.service_sid = @service_sid

			# Create an Access Token
			token = Twilio::JWT::AccessToken.new(
			  @account_sid,
			  @api_key,
			  @api_secret,
			  [grant],
			  identity: identity
			)

			# Generate the token
			token = token.to_jwt

			logger.info token.inspect

			render json: token.as_json

	end


	# Generamos el usuario en twilio
	def generate_user_in_twilio(id)

		set_account

		user = User.find(id)

		if user

		   begin
		      user_twilio = @client.conversations.users.create(identity: id)
		      user.update(twilio_sid: user_twilio.sid)
		   rescue
		    	logger.info "ERROR creating user twilio"
		   end
		else

			# KO

		end

	end


	# Crea una conversación entre dos usuarios y los añade a los dos.
	def create_conversation(user_id1, user_id2)

		set_account

		unique_name = user_id1.to_s+'@'+user_id2.to_s

		begin # La conversacion existe.

		   conversation = @client.conversations
                      .conversations(unique_name)
                      .fetch

		rescue # Conversacion no encontrada, creamos. 

		 conversation = @client.conversations
		  .conversations
		  .create(
		     unique_name: unique_name
		   )


		end

		begin
		# Agregamos los dos usuarios a la conversación
		@client.conversations
                     .conversations(conversation.sid)
                     .participants
                     .create(
                        identity: user_id1,
                      )
      rescue
      	logger.info "Error adding participant 1 "+user_id1.inspect
      end


      begin               
		@client.conversations
                     .conversations(conversation.sid)
                     .participants
                     .create(
                        identity: user_id2,
                      )
      rescue
      	logger.info "Error adding participant 2 "+user_id2.inspect
      end


		return conversation.sid

	end


	def add_participant_to_conversation(conversation_sid, user_id)
      set_account
		@client.conversations
        .conversations(conversation_sid)
        .participants
        .create(
          identity: user_id
         )

	end



	# Añade un mensaje a una conversación. Se usa en el momento del match para mandar un primer mensajito.
	def send_message_to_conversation(sid, user_id, message)
		set_account

		message = @client.conversations
                 .conversations(sid)
                 .messages
                 .create(author: user_id, body: message)

        return message

	end




	# Elimina una conversación
	def destroy_conversation(sid)
		set_account
		@client.conversations.conversations(sid)
                     .delete
	end



	def destroy_conversations
		set_account
		
		@client.conversations.conversations.list(limit: 200).each do |conv|
			@client.conversations.conversations(conv.sid)
                     .delete
		end

		render json: "OK".to_json

	end



	# Generar mensaje con Team Toppin
	def generate_team_toppin(user_id)

		
		umr = UserMatchRequest.create(is_match: true, match_date: DateTime.now, user_ranking:0, target_user_ranking: 0, user_id: 606, target_user: user_id)
	
		conversation_sid = create_conversation(606, umr.target_user)
		umr.update(twilio_conversation_sid: conversation_sid)

		message = "Bienvenido al dulcísimo mundo de Toppin"

		send_message_to_conversation(conversation_sid, 606, message)

		#redirect_to show_user_path(id: umr.target_user), notice: 'Match generado con éxito.'


	end
	



	private

	def set_account


      @account_sid =  ENV['TWILIO_ACCOUNT_SID']
			auth_token =  ENV['TWILIO_AUTH_TOKEN']

	   @api_key =  ENV['TWILIO_API_KEY']
	   @api_secret =  ENV['TWILIO_API_SECRET']

      # Required for conversations api
      @service_sid =  ENV['TWILIO_SERVICE_SID']


      @client = Twilio::REST::Client.new(@account_sid, auth_token)

			puts "--------------------"
			puts  ENV['TWILIO_SERVICE_SID']
			puts "##################"

		#configuration = @client.conversations
                       #.services(ENV['TWILIO_SERVICE_SID'])
                       #.configuration
                       #.update(reachability_enabled: true)
		

	end

end
