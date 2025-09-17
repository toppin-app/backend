Rails.application.routes.draw do
  namespace :spotify do
    get 'admin_spotify_user_data/index'
    get 'admin_spotify_user_data/show'
    get 'admin_spotify_user_data/new'
    get 'admin_spotify_user_data/create'
    get 'admin_spotify_user_data/edit'
    get 'admin_spotify_user_data/update'
  end
  devise_for :users, controllers: { sessions: 'users/sessions', registrations: 'users/registrations', passwords: 'users/passwords' }

  resources :publis
  resources :complaints
  resources :purchases
  resources :user_match_requests
  resources :user_personal_questions
  resources :user_filter_preferences
  resources :personal_questions
  resources :user_info_item_values
  resources :info_item_values
  resources :info_item_categories
  resources :user_filter_references
  resources :user_interests
  resources :interests
  resources :interest_categories
  resources :user_media
  resources :app_versions, only: [:index, :edit, :update]
  resources :user_watchlists, only: [:create, :show]

  # Spotify para los administradores
  resources :users, except: [:index, :show, :new, :edit, :create, :update, :destroy] do
    resources :admin_spotify_user_data, module: 'spotify', only: [:index, :show, :new, :create, :edit, :update, :destroy]
  end


  root to: 'users#index'

  get '/test' => 'admin#index'
  get '/match_requests_current_user', to: 'user_match_requests#current_user_requests'
  devise_scope :user do
    post '/signup', to: 'users/registrations#create'
    post '/login', to: 'users/sessions#create' # Para obtener el token de inicio de sesión
  end

  # CRONS – deben ir antes del wildcard :id
  get '/users/cron_check_outdated_boosts', to: 'users#cron_check_outdated_boosts'
  get 'users/cron_regenerate_likes', to: 'users#cron_regenerate_likes'
  get 'users/cron_regenerate_superlike', to: 'users#cron_regenerate_superlike'
  get 'users/cron_check_online_users', to: 'users#cron_check_online_users'
  get 'cron_regenerate_monthly_boost', to: 'users#cron_regenerate_monthly_boost'
  get 'cron_regenerate_weekly_super_sweet', to: 'users#cron_regenerate_weekly_super_sweet'

  get '/users' => 'users#index', as: :users
  get '/users/:id' => 'users#show', as: :show_user
  get '/new_user' => 'users#new', as: :new_user
  get '/edit_user' => 'users#edit', as: :edit_user
  post '/create_user' => 'users#create', as: :create_user
  post '/update_user' => 'users#update', as: :update_user
  delete '/destroy_user' => 'users#destroy', as: :destroy_user
  get '/logout'=> 'users#logout', as: :logout
  post '/logout'=> 'users#logout'
  post '/update_location', to: "users#update_location"
  post '/social_login_check', to: 'users#social_login_check'
  post '/update_spotify', to: 'users#update_spotify'
  post '/update_push_preferences', to: 'users#update_push_preferences'
  get '/reset_password_sent', to: 'users#reset_password_sent', as: :reset_password_sent
  get '/password_changed', to: 'users#password_changed', as: :password_changed

  post '/update_current_conversation', to: 'users#update_current_conversation'
  post 'users/resolve_location', to: 'users#resolve_location'

  # Hacer visible / invisible usuario
  post '/toggle_visibility', to: 'users#toggle_visibility'

  # Desactivar publicidad
  post '/toggle_publi', to: 'users#toggle_publi'


  post '/short_info_chat', to: 'users#short_info_chat'
  get '/short_info_chat', to: 'users#short_info_chat'

  # Update usuario desde la app
  put '/users/:id' => 'users#update'
  get 'users/available_publis', to: 'users#available_publis'
  put 'users/mark_publi_viewed', to: 'users#mark_publi_viewed'

  # Eliminar cuenta usuario
  post '/delete_account' => 'users#delete_account'



  get '/user_swipes/:user_id', to: 'users#user_swipes'
  get '/get_user_interests', to: 'user_interests#get_user_interests'
  get '/get_user_filter_preferences', to: 'user_filter_preferences#get_user_filter_preferences'
  get '/user_likes/:id', to: 'user_match_requests#current_user_likes'
  get '/vip_toppins', to: 'users#get_vip_toppins'
  post '/unlock_vip_toppin', to: 'users#unlock_vip_toppin'

  get '/get_user_consumables', to: 'users#get_user_consumables'

  # Tirada a la ruleta
  get '/spin_roulette', to: 'users#spin_roulette'

  post '/validate_image', to: 'users#validate_image'
  get '/validate_image', to: 'users#validate_image'
  get '/detect_nudity', to: 'users#detect_nudity'
  post '/reorder_images', to: 'users#reorder_images'

  # Enviar solicitud de match
  post '/send_match', to: "user_match_requests#send_match"

  # Te devuelve si tienes likes
  get '/have_i_likes', to: "users#have_i_likes"



  get '/get_user_matches', to: "user_match_requests#get_user_matches" # Devuelve tus matches
  get '/get_user_likes', to: "user_match_requests#get_user_likes" # Devuelve la gente a la que le gustas
  get '/get_user_superlikes', to: "user_match_requests#get_user_superlikes" # Devuelve las personas que te han dado superlike


  get '/get_user/:id', to: 'users#get_user'
  get '/create_match', to: 'users#create_match', as: :create_match
  post '/create_like', to: 'users#create_like'
  get 'users/:id/matches_status', to: 'users#matches_status'

  post '/reject_match', to: "user_match_requests#reject_match" # Deshacer un match

  post 'users/send_phone_verification', to: 'users#send_phone_verification'
  post 'users/verify_phone_code', to: 'users#verify_phone_code'
  
  # Boosts y superlikes

  # Usar un boost
  post '/use_boost', to: 'users#use_boost'
  get '/time_to_end_boost', to: 'users#time_to_end_boost'

  get '/dc', to: 'twilio#destroy_conversations'
  post '/twilio_webhook', to: 'twilio#twilio_webhook'
  get 'admin/conversation_messages/:conversation_sid', to: 'admin#conversation_messages'

  # Primer mensaje a un match. Params: id, message (El id del user_match_request)
  post '/send_first_message_to_match', to: "user_match_requests#send_first_message_to_match"



  # Aceptar un superlike y mandarle el primer mensaje. Params: id (umr), message
  post '/send_first_message_to_superlike', to: "user_match_requests#send_first_message_to_superlike"


  get '/generate_access_token', to: "twilio#generate_access_token"


  # CRONS
  get '/users/cron_check_outdated_boosts', to: 'users#cron_check_outdated_boosts'
  get '/cron_check_outdated_boosts', to: 'users#cron_check_outdated_boosts'
  get 'users/cron_regenerate_superlike', to: 'users#cron_regenerate_superlike'
  get 'users/cron_regenerate_likes', to: 'users#cron_regenerate_likes'
  get '/cron_recalculate_popularity', to: "users#cron_recalculate_popularity"
  post '/cron_randomize_bundled_users_geolocation', to: 'users#cron_randomize_bundled_users_geolocation'
  get '/cron_check_online_users', to: 'users#cron_check_online_users'
  # Registrar dispositivo para notificaciones push.
  # user_id, token, so, device_uid
  post '/register_device' => 'users#register_device'


  get '/test_conversation', to: "admin#test_conversation"


  # Rutas UserMainInterests para los usuarios de la API
  get '/user_main_interests', to: 'user_main_interests#index', as: :user_main_interests
  get '/user_main_interests/:id', to: 'user_main_interests#show', as: :user_main_interest
  get '/user_main_interests/user/:user_id', to: 'user_main_interests#user_data', as: :user_user_main_interests
  post '/user_main_interests', to: 'user_main_interests#create'
  post '/user_main_interests/bulk_create', to: 'user_main_interests#bulk_create'
  put '/user_main_interests/:id', to: 'user_main_interests#update'
  patch '/user_main_interests/:id', to: 'user_main_interests#update'
  delete '/user_main_interests/:id', to: 'user_main_interests#destroy'
  delete '/user_main_interests', to: 'user_main_interests#destroy_all'


  # Rutas Spotify para los usuarios de la API
  get '/spotify_user_data', to: 'spotify_user_data#index', as: :spotify_user_data
  get '/spotify_user_data/:id', to: 'spotify_user_data#show', as: :spotify_user_datum
  get '/spotify_user_data/user/:user_id', to: 'spotify_user_data#user_data', as: :user_spotify_user_data
  post '/spotify_user_data', to: 'spotify_user_data#create'
  post '/spotify_user_data/bulk_create', to: 'spotify_user_data#bulk_create'
  put '/spotify_user_data/:id', to: 'spotify_user_data#update'
  patch '/spotify_user_data/:id', to: 'spotify_user_data#update'
  delete '/spotify_user_data/:id', to: 'spotify_user_data#destroy'
  delete '/spotify_user_data', to: 'spotify_user_data#destroy_all'



  get '/app_version', to: 'app_versions#show'
  post '/app_version', to: 'app_versions#show'

  get '/tmdb/token', to: 'tmdb#token'
    # Rutas para videollamadas
  post '/video_calls', to: 'video_calls#create'                  # Iniciar llamada
  post '/video_calls/accept', to: 'video_calls#accept'          # Aceptar llamada
  post '/video_calls/reject', to: 'video_calls#reject'          # Rechazar llamada
  post '/video_calls/cancel', to: 'video_calls#cancel'          # Cancelar llamada
  post '/video_calls/end_call', to: 'video_calls#end_call'      # Finalizar llamada
  get  '/video_calls/active', to: 'video_calls#active'       # Ver si el usuario está en una llamada activa
  post '/video_calls/generate_token', to: 'video_calls#generate_token'  # Obtener token de llamada
  get '/video_calls/match_status', to: 'video_calls#match_status'  # Ver estado de la llamada entre dos usuarios

  # Rutas Stripe
  post '/stripe/create_payment_session', to: 'stripe#create_payment_session'
  post '/stripe/ensure_customer', to: 'stripe#ensure_customer'
  get '/stripe/publishable_key', to: 'stripe#publishable_key'
  post '/stripe/webhook', to: 'stripe_webhooks#receive'
  get '/purchases_stripe/status/:payment_id', to: 'purchases_stripe#status'
  get '/stripe/subscription_status', to: 'stripe#subscription_status'
  post '/stripe/cancel_subscription', to: 'stripe#cancel_subscription'

  # Rutas para token spoti
  get '/spotify/token', to: 'spotify#token'

  # Rutas para publicidad
  get 'users/available_publis', to: 'users#available_publis'
  put 'users/mark_publi_viewed', to: 'users#mark_publi_viewed'
  # Rutas TMDB User Data
  get    '/tmdb_user_data',              to: 'tmdb_user_data#index'
  get    '/tmdb_user_data/:id',          to: 'tmdb_user_data#show'
  get    '/tmdb_user_data/user/:user_id',to: 'tmdb_user_data#user_data'
  post   '/tmdb_user_data',              to: 'tmdb_user_data#create'
  post   '/tmdb_user_data/bulk_create',  to: 'tmdb_user_data#bulk_create'
  put    '/tmdb_user_data/:id',          to: 'tmdb_user_data#update'
  patch  '/tmdb_user_data/:id',          to: 'tmdb_user_data#update'
  delete '/tmdb_user_data/:id',          to: 'tmdb_user_data#destroy'
  delete '/tmdb_user_data',              to: 'tmdb_user_data#destroy_all'

  # Rutas TMDB User Series Data
  get    '/tmdb_user_series_data',               to: 'tmdb_user_series_data#index'
  get    '/tmdb_user_series_data/:id',           to: 'tmdb_user_series_data#show'
  get    '/tmdb_user_series_data/user/:user_id', to: 'tmdb_user_series_data#user_data'
  post   '/tmdb_user_series_data',               to: 'tmdb_user_series_data#create'
  post   '/tmdb_user_series_data/bulk_create',   to: 'tmdb_user_series_data#bulk_create'
  put    '/tmdb_user_series_data/:id',           to: 'tmdb_user_series_data#update'
  patch  '/tmdb_user_series_data/:id',           to: 'tmdb_user_series_data#update'
  delete '/tmdb_user_series_data/:id',           to: 'tmdb_user_series_data#destroy'
  delete '/tmdb_user_series_data',               to: 'tmdb_user_series_data#destroy_all'

  #Rutas rate limit tester
  #get '/rate_limit_tester/spotify', to: 'rate_limit_tester#spotify'
  #get '/rate_limit_tester/tmdb', to: 'rate_limit_tester#tmdb'
end
