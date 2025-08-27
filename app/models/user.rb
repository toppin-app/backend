class User < ApplicationRecord

  geocoded_by :locality, latitude: :lat, longitude: :lng

  attr_accessor :unlocked

  # relations
  has_many :user_match_requests, dependent: :destroy
  has_many :user_interests, dependent: :destroy
  has_many :user_main_interests, dependent: :destroy
  has_many :user_media, dependent: :destroy
  has_many :devices, dependent: :destroy
  has_one :user_filter_preference, dependent: :destroy
  has_many :user_info_item_values, dependent: :destroy
  has_many :purchases, dependent: :destroy
  has_many :user_vip_unlocks, dependent: :destroy
  has_many :spotify_user_data, dependent: :destroy
  has_many :tmdb_user_data, class_name: 'TmdbUserDatum', foreign_key: :user_id, dependent: :destroy
  has_many :tmdb_user_series_data, class_name: 'TmdbUserSeriesDatum', foreign_key: :user_id, dependent: :destroy
  mount_base64_uploader :verification_image, ImageUploader
  # Model enums
  enum gender: { female: 0, male: 1, non_binary: 2, couple: 3 }
  enum popularity: { low_popularity: 0, medium_popularity: 1, high_popularity: 2 }
  enum activity_level: { low_activity: 0, medium_activity: 1, high_activity: 2 }
  enum language: { ES: 0, EN: 1}
  serialize :favorite_languages, Array


  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  include Devise::JWT::RevocationStrategies::JTIMatcher
  devise :database_authenticatable, :registerable, :trackable,
         :recoverable, :rememberable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: self

  validate :password_complexity
  # Scope para filtrar por fecha de nacimiento.
  scope :born_between, -> (start_date, end_date)  { where("birthday BETWEEN ? AND ?", start_date, end_date ) }
  scope :active, -> { where(blocked: false) }
  scope :visible, -> { where(hidden_by_user: false) }
  scope :bundled, -> { where(bundled: true) }
  scope :with_likes, -> { where("id in (select target_user FROM user_match_requests)") }
  #before_update :recalculate_percentage
  after_create :create_filters
  before_destroy :destroy_match_requests



  def password_complexity
      return if password.blank?

      regex = /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_\-=\[\]{};':"\\|,.<>\/?]).{8,}\z/
      unless password.match(regex)
        errors.add :password, "debe tener al menos 8 caracteres, una minúscula, una mayúscula, un número y un carácter especial."
      end
  end

  def id_with_name
    "#{id} # #{name}"
  end

  def gender_preferences
    user_filter_preferences&.gender_preferences
  end


  def is_premium

    if self.current_subscription_name.present?
      return true
    end


     if !self.current_subscription_id.present? or !self.current_subscription_name.present?
      return false
     else
      return true
    end
  end



  # Nos dice si un usuario tiene likes de otros usuarios.
  def has_likes
    if self.incoming_likes.any?
      return true
    else
      return false
    end
  end


  # Método para incrementar consumibles.
  def increase_consumable(consumable,units)

    if consumable == "boosters"
      self.update(boost_available: self.boost_available+units)
    end

    if consumable == "superlikes"
      self.update(superlike_available: self.superlike_available+units)
    end

    if consumable == "roulette"
      self.update(spin_roulette_available: self.spin_roulette_available+units)
    end

    if consumable == "likes"
      self.update(likes_left: self.likes_left+units)
    end

  end



  # Al registrarse un user nuevo, que se cree su tabla de filtros.
  def create_filters
    UserFilterPreference.create(user_id: self.id, age_from: 18, age_till: 70, distance_range: 30, interests: "{\"interests\":[]}", categories: "{\"categories\":[]}")
  end


  # ELimina los user_match_request hacia un user cuando este se elimina.
  def destroy_match_requests
    UserMatchRequest.where(target_user: self.id)
  end


  # Porcentaje de completado del perfil.
  def recalculate_percentage

    score = 10

    if self.user_media.any?
      score = score+20
    end

    if self.user_interests.any?
      score = score+20
    end

    if self.description.present?
      score = score + 20
    end

    if self.user_info_item_values.count == 13
       score = score+20
    end

    if self.user_info_item_values.count > 5 and self.user_info_item_values.count < 13
       score = score+10
    end

    self.profile_completed = score

  end


  # Implementación de rekognition para detectar contenido inapropiado en las fotos.
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



def favorite_languages_array
  value = self[:favorite_languages]
  if value.is_a?(String)
    value.split(',').map(&:strip)
  elsif value.is_a?(Array)
    value
  else
    []
  end
end

def favorite_languages
  favorite_languages_array
end

  def location_name
  return "" unless lat.present? && lng.present?
  url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=#{lat}&lon=#{lng}"
  response = HTTParty.get(url, headers: { "User-Agent" => "YourAppName" })
  if response.success? && response['address']
    address = response['address']
    # Puedes ajustar los campos según lo que devuelva Nominatim
    town = address['town'] || address['village'] || address['hamlet'] || address['city']
    city = address['city'] || address['county'] || address['state']
    result = [town, city].compact.uniq.join(', ')
    result.presence || "#{lat} / #{lng}"
  else
    "#{lat} / #{lng}"
  end
end
  

  # Método para usar un boost
  def use_boost

    if self.boost_available > 0 and !self.high_visibility

        self.high_visibility = true
        self.high_visibility_expire = DateTime.now+30.minutes
        self.boost_available = self.boost_available - 1
        self.save
        return true

    else
      return false
    end
  end

  # Time to expire boost
  def time_to_end_boost
    remaining_time = nil
    if self.high_visibility
        boost_expire_time = self.high_visibility_expire
        remaining_time = ((boost_expire_time - Time.now)).to_i
        remaining_time = remaining_time < 1 ? nil : Time.at(remaining_time).utc.strftime("%M:%S");
    end
    return remaining_time
  end



  # Método para usar un superlike
  def use_superlike

    if self.superlike_available > 0

        self.superlike_available = self.superlike_available - 1
        self.last_superlike_given = DateTime.now
        self.save
        return true

    else
      return false
    end
  end

  def recalculate_popularity

   # total_likes = UserMatchRequest.count
    #avg_users = UserMatchRequest.group(:target_user).count

    #avg_users.each do |u|
    #  likes = likes+u[1]
    #end

   # average = total_likes / User.with_likes.count

   # average_min = average / 1.25
    #average_max = average * 1.50

    user_likes = self.incoming_likes.count

    created_at = self.created_at.to_date
    days = (DateTime.now.to_date-created_at).to_i


    ratio = user_likes.to_f / days.to_f


    self.update(incoming_likes_number: user_likes, ratio_likes: ratio)



=begin
    case user_likes # a_variable is the variable we want to compare
    when 0..average_min
      self.update(popularity: 0)
    when average_min..average_max
      self.update(popularity: 1)
    when average_max..100000
      self.update(popularity: 2)
    end
=end



  end



  # Recalcula el ranking de un usuario
  def recalculate_ranking

    media = self.user_media.count
    score = self.ranking_matches

    logger.info score.inspect

    if media == 1
      score = score+1
    end
    logger.info score.inspect
    if media > 1
      score = score+2
    end
    logger.info score.inspect
    if self.description and self.description.length > 30
      score = score + 2
    end
    logger.info score.inspect

    if self.high_visibility
      score = score + 5
    end
    logger.info score.inspect

    if self.activity_level == 2
      score = score + 2
    end
    logger.info score.inspect


    score = score + self.ranking_incoming_likes
    logger.info score.inspect


    # PENDIENTE:
     # - PAGOS
     # - RECHAZOS
     # - DENUNCIAS
     # - Rango de fechas


    self.ranking = score.round
    self.save

    return score

  end


  def self.count_matches
     User.all.each do |u|
      u.matches_number = u.matches.count
      u.incoming_match_request_number = u.incoming_likes.count
      u.save
     end
  end

  def premium_or_supreme?
    current_subscription_name&.in?(%w[premium supreme])
  end

  # Nos devuelve la puntuación que le damos por la cantidad y calidad de los likes que tiene el usuario
  # (Personas a las que le gusta el usuario.)
  def ranking_incoming_likes
  likes = self.incoming_likes

  return 0 unless likes.any?

  # Extraemos el ranking medio de los usuarios a los que le gustamos.
  average = likes.average(:user_ranking).to_f 

  # Puntos max del average: 5
  score = average * 5 / 100

  # Ahora vamos con la media de likes, si tenemos más de la media, le damos 5 puntos extra.
  incoming_likes = self.incoming_likes.count
  average_incoming_likes = User.all.average(:incoming_match_request_number).to_f

  score += 5 if incoming_likes > average_incoming_likes

  score.to_f
end




  # Nos devuelve la puntuación del user en base a sus matches.
  # Máximo que puede devolver: 80
  def ranking_matches

    sent = self.sent_matches.average(:target_user_ranking).to_i
    received = self.received_matches.average(:user_ranking).to_i

    average = (sent+received)/2

    average = average.to_i

    # max del average: 72
    score = average * 72 / 100

    # max del porcentaje: 8
    matches = self.matches.count
    average_matches = User.all.average(:matches_number).to_f

    if matches > average_matches
      score = score + 8
    end

    return score
  end


  def incoming_likes
    return UserMatchRequest.where(target_user: id, is_match: [nil,false], is_like: true)
  end


  # User match requests dados o recibidos por el usuario, sin filtros.
  def given_received_requests
     return UserMatchRequest.where("user_id = ? or target_user = ?", self.id, self.id)
  end


  # Likes enviados o dislikes por el usuario.
  def sent_likes
     return UserMatchRequest.where(user_id: self.id)
  end


  # Nos devuelve los matches de un usuario
  def matches
     #self.sent_matches+self.received_matches
     UserMatchRequest.where("user_id = ? or target_user = ?", self.id, self.id).where("is_match IS TRUE OR is_sugar_sweet IS TRUE or is_superlike IS TRUE").where(is_rejected: false).order(id: :desc).eager_load(:user)
  end

  # Matches del usuario cuando ha iniciado el mismo.
  def sent_matches
    UserMatchRequest.where(user_id: id).where("is_match IS TRUE OR is_sugar_sweet IS TRUE or is_superlike IS TRUE").where(is_rejected: false).order(id: :desc).eager_load(:user)
  end

  # Matches del usuario cuando lo ha iniciado el otro usuario.
  def received_matches
    UserMatchRequest.where(target_user: id).where("is_match IS TRUE OR is_sugar_sweet IS TRUE or is_superlike IS TRUE").where(is_rejected: false).order(id: :desc).eager_load(:user)
  end


  def received_sugar_sweets
    UserMatchRequest.where(target_user: id).where("is_match IS FALSE AND is_sugar_sweet IS TRUE").where(is_rejected: false).pluck(:user_id)
  end


  # user.rb
  def jwt_payload
    self.jti = self.class.generate_jti
    self.save

    # super isn't doing anything useful, but if the gem updates i'll want it to be safe
    super.merge({
      jti: self.jti,
      usr: self.id,
    })
  end

  # Edad del usuario
  def user_age

    if self.birthday.blank?
      return " - "
    end


    birthday = self.birthday
    return ((Time.zone.now - birthday.to_time) / 1.year.seconds).floor
  end


  def user_media_url
    return 'https://web-backend-ruby.uao3jo.easypanel.host'
  end

  def profile_picture
      self.user_media.first.file.url if self.user_media.any?
  end

  def profile_picture_thumb
      self.user_media.first.file.thumb.url if self.user_media.any?
  end

   def gender_t
      if gender == "female"
        return "Mujer"
      end
      if gender == "male"
        return "Hombre"
      else
        return gender
      end
    end



  # Checkea si un user está online en twilio.
  def online_in_twilio
      @account_sid = 'AC856674e42d06d3ad5e9e6715e653271f'
      auth_token = '1770aef21ce5a3dbc343da7306d0a392'
      # Required for conversations api
      @service_sid = 'IS3215a77e05c34d53a5629c1f67aa49ee'


      @client = Twilio::REST::Client.new(@account_sid, auth_token)
      user = @client.conversations.users(self.id).fetch

      return user.is_online
  end



  def username
    self.user_name
  end
end
