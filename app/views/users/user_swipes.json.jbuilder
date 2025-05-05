index_user = 0
current_publi = 0
publi = @publis[current_publi]



json.users @users do |user|


	   if publi and (index_user > 1 and index_user % publi.repeat_swipes == 0)

	   		logger.info "APLICO PUBLI en index #{index_user} = "+publi.inspect

	    	json.publi publi, :id, :image_complete, :video, :link, :cancellable
	    	current_publi = current_publi + 1

	    	if @publis[current_publi].nil?
	    		current_publi = 0
	    	end

	    	publi = @publis[current_publi]
	   else
	   	  json.extract! user, :id, :email, :name, :username, :blocked, :profile_completed, :phone, :phone_validated,:superlike_available, :current_subscription_name, :verified, :verification_file, :push_token, :device_id, :device_platform, :description, :gender, :high_visibility, :hidden_by_user, :is_connected, :last_connection, :last_match, :is_new, :activity_level, :birthday, :user_age, :born_in, :living_in, :locality, :country, :lat, :lng, :occupation, :studies, :popularity, :user_media, :user_media_url, :user_interests, :user_info_item_values, :spoty1, :spoty2, :spoty3, :spoty4,  :spoty_title1, :spoty_title2, :spoty_title3, :spoty_title4, :location_city, :location_country
	   end
	
	   index_user = index_user +1

	


end
	
