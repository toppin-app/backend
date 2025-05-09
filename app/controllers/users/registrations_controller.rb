class Users::RegistrationsController < Devise::RegistrationsController
    skip_before_action :verify_authenticity_token, :only => :create
    before_action :sign_up_params
    respond_to :json

    def create
        ActiveRecord::Base.transaction do

            build_resource(sign_up_params)

            resource.name = params[:user][:name]
            resource.email = params[:user][:email]
            resource.gender = params[:user][:gender]
            resource.birthday = params[:user][:birthday]
            resource.push_token = params[:user][:push_token]
            resource.device_id = params[:user][:device_id]
            resource.lat = params[:user][:lat]
            resource.lng = params[:user][:lng]

            if params[:user][:social]
                resource.social = params[:user][:social]
                resource.password = Digest::SHA1.hexdigest([Time.now, rand].join) # Random password
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

            resource.high_visibility = true # Allow high visibility
            #resource.high_visibility_expire = Date.today.next_day(7).strftime("%F") # Set high visibility to expire in 1 week

            # Le daremos boost al usuario durante sus primeras 3 horas.
            resource.high_visibility_expire = DateTime.now+3.hours



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

                # Save profile image
                media = UserMedium.create!(
                    user_id: resource.id,
                    file: params[:user][:file],
                    position: 0
                )

                result = User.find(resource.id).detect_nudity

                if !result
                    media.destroy
                end

            resource.user_filter_preference.update(gender: params[:user][:gender_filter])

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

            if params[:user][:user_main_interests]
                interests_with_user_id = params[:user][:user_main_interests].map do |interest|
                    interest.merge(user_id: resource.id)
                end

                user_main_interests_controller = UserMainInterestsController.new
                user_main_interests_controller.request = request
                user_main_interests_controller.response = response
                result = user_main_interests_controller.bulk_create(user_main_interests: interests_with_user_id)

                raise ActiveRecord::Rollback unless result
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
