class Users::RegistrationsController < Devise::RegistrationsController
    skip_before_action :verify_authenticity_token, :only => :create
    before_action :sign_up_params
    respond_to :json

    def create
        ActiveRecord::Base.transaction do
            # Validar que el teléfono haya sido verificado ANTES del registro
            phone_number = params[:user][:phone]
            
            if phone_number.present?
                verified_phone = PhoneVerification.for_phone(phone_number)
                                                 .where(verified: true)
                                                 .order(created_at: :desc)
                                                 .first
                
                unless verified_phone
                    render json: { 
                        status: 403, 
                        error: 'Debes verificar tu número de teléfono antes de registrarte',
                        code: 'PHONE_NOT_VERIFIED'
                    }, status: :forbidden
                    return
                end
            end

            build_resource(sign_up_params)

            resource.name = params[:user][:name]
            resource.email = params[:user][:email]
            resource.phone = params[:user][:phone] # Guardar teléfono verificado
            resource.gender = params[:user][:gender]
            resource.birthday = params[:user][:birthday]
            resource.push_token = params[:user][:push_token]
            resource.device_id = params[:user][:device_id]
            # El callback detect_device_platform detectará automáticamente la plataforma basado en device_id
            # Si viene explícitamente en params, lo usamos
            resource.device_platform = params[:user][:device_platform] if params[:user][:device_platform]
            resource.lat = params[:user][:lat]
            resource.lng = params[:user][:lng]
            resource.language = params[:user][:language] || "ES" #TODO cambiar por el idioma del dispositivo
            if params[:user][:social]
                resource.social = params[:user][:social]
                resource.password = SecureRandom.urlsafe_base64(32)
                resource.save
            end


            if params[:user][:social_login_token]
                resource.social_login_token = params[:user][:social_login_token]
            end


            if params[:user][:social] and params[:user][:social] == "apple"
                at = AppleToken.where(token: params[:user][:social_login_token], email: params[:user][:email])
                if !at.any?
                AppleToken.create(token: params[:user][:social_login_token], email: params[:user][:email])
                end
            end



            # Set default params
            resource.is_connected = true # Set user online


            # seteamos el user_name a partir del name y el lastname
            # resource.user_name = "#{resource.name}#{resource.lastname}"
            fullname = "#{resource.name}"
            resource.user_name = fullname.split(" ").join.downcase
            # comprobamos si existe un user_name igual y le añadimos el numero siguiente para distinguirlos
            check_unique_users = User.where("user_name like ?", "#{resource.user_name}%").count

            if check_unique_users > 0
                resource.user_name = resource.user_name + (check_unique_users + 1).to_s
            end

            # Cambio solicitado David. Ahora los users tienen 20 superlikes cuando se registran.
            resource.superlike_available = 20

            resource.save!

            if resource.persisted?
                # Manejar múltiples archivos de imagen
                files = params[:user][:files] || (params[:user][:file] ? [params[:user][:file]] : [])
                
                if files.present?
                    files.each_with_index do |file, index|
                        # Detectar desnudos en cada imagen
                        if resource.detect_nudity(file)
                            render json: { status: 400, message: "Una o más imágenes contienen desnudos y no pueden subirse." }, status: :bad_request
                            raise ActiveRecord::Rollback
                        end

                        # Crear el media con la posición correspondiente
                        UserMedium.create!(
                            user_id: resource.id,
                            file: file,
                            position: index
                        )
                    end
                end

                allowed_genders = ["male", "female", "non_binary", "couple"]
                selected_genders = params[:user][:gender_filter] # Esto ahora será un array o una cadena

                    allowed_genders = ["male", "female", "non_binary","couple"]
                    selected_genders = params[:user][:gender_filter]

                    # Aseguramos que selected_genders sea un array para poder iterar sobre él
                    selected_genders =
                    if selected_genders.is_a?(String)
                        selected_genders.split(',') # ej. "male,female" => ["male", "female"]
                    elsif selected_genders.is_a?(Array)
                        selected_genders
                    else
                        render json: { error: "Formato de género no válido." }, status: :unprocessable_entity
                        raise ActiveRecord::Rollback
                    end

                    # Verificamos que cada género en el array sea permitido
                    unless selected_genders.all? { |gender| allowed_genders.include?(gender) }
                    render json: { error: "Uno o más géneros seleccionados no son válidos." }, status: :unprocessable_entity
                    raise ActiveRecord::Rollback
                    end

                    # Guardamos los géneros como una cadena separada por comas (ej. "male,female")
                    resource.user_filter_preference.update(gender_preferences: selected_genders.join(','))

=begin
            # Save gender filter preference data
            UserFilterPreference.create(
                user_id: resource.id,
                gender: params[:user][:gender_filter],
                distance_range: 5,
                age_from: 18,
                age_till: 99
            )
=end



            twilio = TwilioController.new
            twilio.generate_user_in_twilio(resource.id)

            twilio.generate_team_toppin(resource.id)

            if params[:user][:user_main_interests].blank? || params[:user][:user_main_interests].empty?
                render json: { error: "user_main_interests no puede estar vacío" }, status: :unprocessable_entity
                return
            end

            # Si pasa la validación, se procede a crear el usuario
            if resource.save
                interests_with_user_id = params[:user][:user_main_interests].map do |interest|
                interest.merge(user_id: resource.id)
            end

            user_main_interests_controller = UserMainInterestsController.new
            user_main_interests_controller.request = request
            user_main_interests_controller.response = response
            result = user_main_interests_controller.bulk_create(user_main_interests: interests_with_user_id)

            unless result
                raise ActiveRecord::Rollback
            end
            
            # Enviar email de bienvenida
            begin
                WelcomeMailer.welcome_email(resource).deliver_now
                Rails.logger.info "Email de bienvenida enviado a: #{resource.email}"
            rescue StandardError => e
                Rails.logger.error "Error enviando email de bienvenida: #{e.message}"
                Rails.logger.error e.backtrace.join("\n")
                # No lanzamos error para no interrumpir el registro
            end
            
            else
            # manejar errores de creación de usuario
            end

            sign_in(resource)
            render 'users/show'
            #render json: resource, status: :created
            else
                raise ActiveRecord::Rollback
            end
        end
        rescue ActiveRecord::RecordInvalid
            if User.find_by(email: params[:user][:email])
                msg = "USER_EXISTS"
                status = :unprocessable_entity
            else
                msg = "UNKNOWN_ERROR"
                status = :not_implemented
            end
            render json: {status: 'KO', msg: msg}, status: status
        end


    def sign_up_params
        devise_parameter_sanitizer.sanitize(:sign_up)
    end

end
