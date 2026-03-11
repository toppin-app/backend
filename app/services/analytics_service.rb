class AnalyticsService
  # Filter parameters helper
  # Filters are OPTIONAL and ADDITIVE - only apply when explicitly set
  def self.apply_filters(scope, filters)
    Rails.logger.debug "ANALYTICS SERVICE - apply_filters called with:"
    Rails.logger.debug "  filters: #{filters.inspect}"
    Rails.logger.debug "  initial scope SQL: #{scope.to_sql}" rescue nil
    
    # Account status filters (mutually exclusive)
    if filters[:exclude_deleted] == true
      scope = scope.where(deleted_account: false)
    elsif filters[:only_deleted] == true
      scope = scope.where(deleted_account: true)
    end
    # If both are false or nil, show ALL accounts
    
    # Bot filters (mutually exclusive)
    if filters[:exclude_bots] == true
      scope = scope.where(fake_user: false)
    elsif filters[:only_bots] == true
      scope = scope.where(fake_user: true)
    end
    # If both are false or nil, show ALL users (bots and real)
    
    # Optional filters - only apply when explicitly set
    scope = scope.where(gender: filters[:gender]) if filters[:gender].present?
    scope = scope.where(device_platform: filters[:device_platform]) if filters[:device_platform].present?
    scope = scope.where(verified: true) if filters[:verified] == true
    scope = scope.where(verified: false) if filters[:verified] == false
    scope = scope.where('location_country = ?', filters[:country]) if filters[:country].present?
    scope = scope.where('location_city = ?', filters[:city]) if filters[:city].present?
    
    # Subscription filter
    if filters[:subscription_type].present?
      case filters[:subscription_type]
      when 'free'
        scope = scope.where(current_subscription_name: nil)
      when 'premium'
        scope = scope.where(current_subscription_name: 'premium')
      when 'supreme'
        scope = scope.where(current_subscription_name: 'supreme')
      end
    end
    
    # NOTE: Date filtering is handled by apply_date_range only
    # Do NOT filter by dates here to avoid double filtering
    
    Rails.logger.debug "ANALYTICS SERVICE - Final filtered scope SQL:"
    Rails.logger.debug scope.to_sql rescue "Could not generate SQL"
    Rails.logger.debug "="*80
    
    scope
  end

  # ===== GROWTH METRICS =====
  
  def self.new_users_over_time(filters = {}, group_by = :day)
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    case group_by
    when :day
      scope.group("DATE(created_at)").count
    when :week
      scope.group("YEARWEEK(created_at)").count
    when :month
      scope.group("DATE_FORMAT(created_at, '%Y-%m')").count
    end
  end

  def self.cumulative_users(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    users_by_day = scope.group("DATE(created_at)").count
    cumulative = {}
    total = 0
    users_by_day.sort.each do |date, count|
      total += count
      cumulative[date.to_s] = total
    end
    cumulative
  end

  def self.user_count_metrics(filters = {})
    # CORRECT PATTERN: User.all → apply_filters → apply_date_range
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    # ALL metrics use the filtered scope
    total_users = scope.count
    
    # Breakdown by type - counts within filtered dataset
    # Note: If user selected "Only Bots", real_users will be 0
    # Note: If user selected "Exclude Bots", bot_users will be 0
    real_users = scope.where(fake_user: false, deleted_account: false).count
    bot_users = scope.where(fake_user: true).count
    verified_users = scope.where(verified: true, deleted_account: false).count
    deleted_users = scope.where(deleted_account: true).count
    
    {
      total_users: total_users,
      real_users: real_users,
      bot_users: bot_users,
      verified_users: verified_users,
      deleted_users: deleted_users
    }
  end

  def self.users_by_type(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    # Apply ALL filters to get the base filtered dataset
    # Then break it down by type
    filtered_scope = apply_filters(scope, filters)
    
    # Count each type within the filtered dataset
    # If user excluded bots, bots count will be 0
    # If user excluded deleted, deleted count will be 0
    {
      real: filtered_scope.where(fake_user: false, deleted_account: false).count,
      bots: filtered_scope.where(fake_user: true).count,
      deleted: filtered_scope.where(deleted_account: true).count
    }
  end

  def self.verified_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    
    {
      verified: scope.where(verified: true).count,
      non_verified: scope.where(verified: false).count
    }
  end

  def self.deletions_over_time(filters = {})
    # Start with all users, apply filters, then restrict to deleted
    scope = User.all
    scope = apply_filters(scope, filters)
    # Only show deletions (but respecting other filters like gender, country, etc)
    scope = scope.where(deleted_account: true)
    scope = apply_date_range(scope, filters, :updated_at)
    
    scope.group("DATE(updated_at)").count
  end
  
  # ===== DEMOGRAPHICS =====
  
  def self.gender_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters.except(:gender))
    scope = apply_date_range(scope, filters, :created_at)
    
    scope.group(:gender).count
  end

  def self.age_distribution(filters = {})
    # Start with all users, apply filters properly
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without birthday AFTER applying user filters
    scope = scope.where.not(birthday: nil)
    
    users = scope.select(:birthday)
    age_groups = { '18-24' => 0, '25-34' => 0, '35-44' => 0, '45-54' => 0, '55+' => 0 }
    
    users.each do |user|
      age = ((Time.current - user.birthday.to_time) / 1.year).to_i
      case age
      when 18..24 then age_groups['18-24'] += 1
      when 25..34 then age_groups['25-34'] += 1
      when 35..44 then age_groups['35-44'] += 1
      when 45..54 then age_groups['45-54'] += 1
      else age_groups['55+'] += 1 if age >= 55
      end
    end
    
    age_groups
  end

  def self.top_countries(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters.except(:country))
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without country AFTER applying filters
    scope = scope.where.not(location_country: nil)
    
    scope.group(:location_country).count.sort_by { |_, v| -v }.first(limit).to_h
  end

  def self.top_cities(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters.except(:city))
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without city AFTER applying filters
    scope = scope.where.not(location_city: nil)
    
    scope.group(:location_city).count.sort_by { |_, v| -v }.first(limit).to_h
  end

  def self.average_age_by_gender(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    # Filter out users without birthday AFTER applying filters
    scope = scope.where.not(birthday: nil)
    
    result = {}
    User.genders.keys.each do |gender|
      users = scope.where(gender: gender)
      if users.any?
        avg_age = users.average("TIMESTAMPDIFF(YEAR, birthday, CURDATE())").to_f.round(1)
        result[gender] = avg_age
      end
    end
    result
  end

  # ===== TOP INSIGHTS =====
  
  def self.top_users(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters)
    
    {
      most_matches: scope.order(matches_number: :desc).limit(limit).pluck(:id, :name, :matches_number),
      most_liked: scope.order(incoming_likes_number: :desc).limit(limit).pluck(:id, :name, :incoming_likes_number),
      highest_ranking: scope.order(ranking: :desc).limit(limit).pluck(:id, :name, :ranking)
    }
  end

  def self.top_performing_cities(filters = {}, limit = 10)
    scope = User.all
    scope = apply_filters(scope, filters.except(:city))
    scope = scope.where.not(location_city: nil)
    
    cities = scope.group(:location_city).count.sort_by { |_, v| -v }.first(limit)
    
    city_stats = cities.map do |city, count|
      city_users = scope.where(location_city: city)
      avg_matches = city_users.average(:matches_number).to_f.round(2)
      
      {
        city: city,
        users: count,
        avg_matches: avg_matches
      }
    end
    
    city_stats
  end
  
  def self.top_movies(filters = {}, limit = 20)
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    # Get top movies from filtered users
    # Only consider movies (media_type = 'movie')
    TmdbUserDatum
      .where(user_id: user_ids, media_type: 'movie')
      .where.not(title: nil)
      .group(:title)
      .count
      .sort_by { |_, count| -count }
      .first(limit)
      .to_h
  end
  
  def self.top_series(filters = {}, limit = 20)
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    # Get top series from filtered users
    TmdbUserSeriesDatum
      .where(user_id: user_ids)
      .where.not(title: nil)
      .group(:title)
      .count
      .sort_by { |_, count| -count }
      .first(limit)
      .to_h
  end
  
  def self.photos_distribution(filters = {})
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    
    # Initialize valid distribution (1-9 only)
    valid_distribution = {
      '1' => 0,
      '2' => 0,
      '3' => 0,
      '4' => 0,
      '5' => 0,
      '6' => 0,
      '7' => 0,
      '8' => 0,
      '9' => 0
    }
    
    # Initialize invalid distribution (0 and >9)
    invalid_distribution = {
      '0' => 0,
      '>9' => 0
    }
    
    # Store users with invalid photo counts for inspection
    invalid_users = {
      '0' => [],
      '>9' => []
    }
    
    # Count photos per user and populate distributions
    user_scope.includes(:user_media).find_each do |user|
      photo_count = user.user_media.count
      
      if photo_count == 0
        invalid_distribution['0'] += 1
        invalid_users['0'] << {
          id: user.id,
          name: user.name,
          email: user.email
        }
      elsif photo_count > 9
        invalid_distribution['>9'] += 1
        invalid_users['>9'] << {
          id: user.id,
          name: user.name,
          email: user.email,
          photo_count: photo_count
        }
      else
        valid_distribution[photo_count.to_s] += 1
      end
    end
    
    {
      valid: valid_distribution,
      invalid: invalid_distribution,
      invalid_users: invalid_users
    }
  end
  
  # ===== INTERESTS ANALYTICS =====
  
  def self.main_interests_distribution(filters = {}, limit = nil)
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    # Count users per main interest
    distribution = UserMainInterest
      .where(user_id: user_ids)
      .joins(:interest)
      .group('interests.name')
      .count
    
    # Sort by count descending, optionally limit
    sorted = distribution.sort_by { |_, count| -count }
    limit.present? ? sorted.first(limit).to_h : sorted.to_h
  end
  
  def self.secondary_interests_distribution(filters = {}, limit = nil)
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)
    
    # Count users per secondary interest
    distribution = UserInterest
      .where(user_id: user_ids)
      .joins(:interest)
      .group('interests.name')
      .count
    
    # Sort by count descending, optionally limit
    sorted = distribution.sort_by { |_, count| -count }
    limit.present? ? sorted.first(limit).to_h : sorted.to_h
  end
  
  def self.main_interests_count_distribution(filters = {})
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    
    # Valid: exactly 4 main interests
    valid_count = 0
    
    # Invalid distributions: <4 or >4
    invalid_distribution = {
      '<4' => 0,
      '>4' => 0
    }
    
    # Store users with invalid main interests count
    invalid_users = {
      '<4' => [],
      '>4' => []
    }
    
    # Count main interests per user
    user_scope.includes(:user_main_interests).find_each do |user|
      main_interests_count = user.user_main_interests.count
      
      if main_interests_count == 4
        valid_count += 1
      elsif main_interests_count < 4
        invalid_distribution['<4'] += 1
        invalid_users['<4'] << {
          id: user.id,
          name: user.name,
          email: user.email,
          main_interests_count: main_interests_count
        }
      else # main_interests_count > 4
        invalid_distribution['>4'] += 1
        invalid_users['>4'] << {
          id: user.id,
          name: user.name,
          email: user.email,
          main_interests_count: main_interests_count
        }
      end
    end
    
    {
      valid: valid_count,
      invalid: invalid_distribution,
      invalid_users: invalid_users
    }
  end
  
  def self.secondary_interests_count_per_user(filters = {})
    # Get filtered users
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    
    # Initialize distribution for 0-10+ secondary interests
    distribution = {}
    (0..10).each { |i| distribution[i.to_s] = 0 }
    distribution['>10'] = 0
    
    # Count secondary interests per user
    user_scope.includes(:user_interests).find_each do |user|
      secondary_interests_count = user.user_interests.count
      
      if secondary_interests_count > 10
        distribution['>10'] += 1
      else
        distribution[secondary_interests_count.to_s] += 1
      end
    end
    
    distribution
  end
  
  # ===== SPOTIFY ANALYTICS =====

  def self.spotify_artists_count_distribution(filters = {})
    user_scope = apply_filters(User.all, filters)
    user_ids = user_scope.pluck(:id)

    # Count Spotify artists per user
    counts_by_user = SpotifyUserDatum.where(user_id: user_ids)
                                     .group(:user_id).count

    distribution = {}
    (0..10).each { |i| distribution[i.to_s] = 0 }
    distribution['>10'] = 0

    user_ids.each do |uid|
      c = counts_by_user[uid] || 0
      if c > 10
        distribution['>10'] += 1
      else
        distribution[c.to_s] += 1
      end
    end

    distribution
  end

  def self.top_spotify_artists(filters = {}, limit = 10)
    user_ids = apply_filters(User.all, filters).pluck(:id)
    SpotifyUserDatum.where(user_id: user_ids)
                    .group(:artist_name).count
                    .sort_by { |_, v| -v }
                    .first(limit)
                    .to_h
  end

  def self.table_exists?(table_name)
    ActiveRecord::Base.connection.table_exists?(table_name)
  end

  # ===== LANGUAGES ANALYTICS =====

  def self.subscription_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)

    {
      'Gratuito' => scope.where(current_subscription_name: nil).count,
      'Premium'  => scope.where(current_subscription_name: 'premium').count,
      'Supreme'  => scope.where(current_subscription_name: 'supreme').count
    }
  end

  def self.app_language_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)
    scope = scope.where.not(language: nil)

    scope.group(:language).count.sort_by { |_, v| -v }.to_h
  end

  LANGUAGE_NAMES = {
    '1' => 'Abjasio', '2' => 'Afar', '3' => 'Afrikáans', '4' => 'Akan',
    '5' => 'Albanés', '6' => 'Amárico', '7' => 'Árabe', '8' => 'Aragonés',
    '9' => 'Armenio', '10' => 'Asamés', '11' => 'Avar', '12' => 'Avéstico',
    '13' => 'Aimara', '14' => 'Azerí', '15' => 'Bambara', '16' => 'Baskir',
    '17' => 'Euskera', '18' => 'Bielorruso', '19' => 'Bengalí', '20' => 'Bihari',
    '21' => 'Bislama', '22' => 'Bosnio', '23' => 'Bretón', '24' => 'Búlgaro',
    '25' => 'Birmano', '26' => 'Catalán', '27' => 'Chamorro', '28' => 'Checheno',
    '29' => 'Chichewa', '30' => 'Chino', '31' => 'Chuvasio', '32' => 'Córnico',
    '33' => 'Corso', '34' => 'Cree', '35' => 'Croata', '36' => 'Checo',
    '37' => 'Danés', '38' => 'Maldivo', '39' => 'Neerlandés', '40' => 'Dzongkha',
    '41' => 'Inglés', '42' => 'Esperanto', '43' => 'Estonio', '44' => 'Ewé',
    '45' => 'Feroés', '46' => 'Fiyiano', '47' => 'Finés', '48' => 'Francés',
    '49' => 'Fula', '50' => 'Gallego', '51' => 'Georgiano', '52' => 'Alemán',
    '53' => 'Griego', '54' => 'Guaraní', '55' => 'Guyaratí', '56' => 'Haitiano',
    '57' => 'Hausa', '58' => 'Hebreo', '59' => 'Herero', '60' => 'Hindi',
    '61' => 'Hiri Motu', '62' => 'Húngaro', '63' => 'Interlingua', '64' => 'Indonesio',
    '65' => 'Interlingue', '66' => 'Irlandés', '67' => 'Igbo', '68' => 'Inupiaq',
    '69' => 'Ido', '70' => 'Islandés', '71' => 'Italiano', '72' => 'Inuktitut',
    '73' => 'Japonés', '74' => 'Javanés', '75' => 'Groenlandés', '76' => 'Canarés',
    '77' => 'Kanuri', '78' => 'Cachemir', '79' => 'Kazajo', '80' => 'Jemer',
    '81' => 'Kikuyu', '82' => 'Kinyarwanda', '83' => 'Kirguís', '84' => 'Komi',
    '85' => 'Kongo', '86' => 'Coreano', '87' => 'Kurdo', '88' => 'Kuanyama',
    '89' => 'Latín', '90' => 'Luxemburgués', '91' => 'Ganda', '92' => 'Limburgués',
    '93' => 'Lingala', '94' => 'Lao', '95' => 'Lituano', '96' => 'Luba-Katanga',
    '97' => 'Letón', '98' => 'Manés', '99' => 'Macedonio', '100' => 'Malgache',
    '101' => 'Malayo', '102' => 'Malabar', '103' => 'Maltés', '104' => 'Maorí',
    '105' => 'Maratí', '106' => 'Marshalés', '107' => 'Mongol', '108' => 'Nauruano',
    '109' => 'Navajo', '110' => 'Ndebele del norte', '111' => 'Nepalí', '112' => 'Ndonga',
    '113' => 'Noruego Bokmål', '114' => 'Noruego Nynorsk', '115' => 'Noruego',
    '116' => 'Yi de Sichuán', '117' => 'Ndebele del sur', '118' => 'Occitano',
    '119' => 'Ojibwa', '120' => 'Eslavo eclesiástico', '121' => 'Oromo', '122' => 'Oriya',
    '123' => 'Osetio', '124' => 'Punyabí', '125' => 'Pali', '126' => 'Persa',
    '127' => 'Polaco', '128' => 'Pastún', '129' => 'Portugués', '130' => 'Quechua',
    '131' => 'Romanche', '132' => 'Kirundi', '133' => 'Rumano', '134' => 'Ruso',
    '135' => 'Sánscrito', '136' => 'Sardo', '137' => 'Sindhi', '138' => 'Sami septentrional',
    '139' => 'Samoano', '140' => 'Sango', '141' => 'Serbio', '142' => 'Gaélico escocés',
    '143' => 'Shona', '144' => 'Cingalés', '145' => 'Eslovaco', '146' => 'Esloveno',
    '147' => 'Somalí', '148' => 'Sesoto', '149' => 'Español', '150' => 'Sundanés',
    '151' => 'Suajili', '152' => 'Suazi', '153' => 'Sueco', '154' => 'Tamil',
    '155' => 'Telugú', '156' => 'Tayiko', '157' => 'Tailandés', '158' => 'Tigriña',
    '159' => 'Tibetano', '160' => 'Turcomano', '161' => 'Tagalo', '162' => 'Tswana',
    '163' => 'Tongano', '164' => 'Turco', '165' => 'Tsonga', '166' => 'Tártaro',
    '167' => 'Twi', '168' => 'Tahitiano', '169' => 'Uigur', '170' => 'Ucraniano',
    '171' => 'Urdu', '172' => 'Uzbeko', '173' => 'Venda', '174' => 'Vietnamita',
    '175' => 'Volapük', '176' => 'Valón', '177' => 'Galés', '178' => 'Wólof',
    '179' => 'Frisón occidental', '180' => 'Xhosa', '181' => 'Yidis', '182' => 'Yoruba',
    '183' => 'Zhuang', '184' => 'Zulú', '185' => 'Valenciano'
  }.freeze

  def self.profile_languages_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)

    distribution = {}
    scope.pluck(:favorite_languages).each do |raw|
      next if raw.blank?
      parse_favorite_languages(raw).each do |lang|
        name = LANGUAGE_NAMES[lang.to_s] || lang
        distribution[name] ||= 0
        distribution[name] += 1
      end
    end

    distribution.sort_by { |_, v| -v }.to_h
  end

  def self.profile_languages_count_distribution(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters)
    scope = apply_date_range(scope, filters, :created_at)

    distribution = {}
    scope.pluck(:favorite_languages).each do |raw|
      count = raw.blank? ? 0 : parse_favorite_languages(raw).length
      key = count.to_s
      distribution[key] ||= 0
      distribution[key] += 1
    end

    distribution.sort_by { |k, _| k.to_i }.to_h
  end

  # ===== HELPER METHODS =====
  
  private
  
  def self.parse_favorite_languages(raw)
    return [] if raw.blank?

    if raw.is_a?(Array)
      return raw.map(&:to_s).map(&:strip).reject(&:blank?)
    end

    if raw.is_a?(String)
      begin
        parsed = JSON.parse(raw)
        return parsed.map(&:to_s).map(&:strip).reject(&:blank?) if parsed.is_a?(Array)
      rescue JSON::ParserError
        # continue with comma split
      end
      return raw.split(',').map(&:strip).reject(&:blank?)
    end

    []
  end

  def self.apply_date_range(scope, filters, column)
    if filters[:start_date].present? && filters[:end_date].present?
      scope.where("#{column} >= ? AND #{column} <= ?", filters[:start_date], filters[:end_date])
    else
      scope
    end
  end

  def self.get_date_range(filters)
    if filters[:start_date].present? && filters[:end_date].present?
      { 
        start: filters[:start_date], 
        end: filters[:end_date],
        wau_start: [filters[:start_date], 7.days.ago].max,
        mau_start: [filters[:start_date], 30.days.ago].max
      }
    else
      # Default to reasonable ranges for engagement metrics
      { 
        start: 1.day.ago,  # DAU - last 24 hours
        wau_start: 7.days.ago,   # WAU - last 7 days
        mau_start: 30.days.ago,  # MAU - last 30 days
        end: Time.current 
      }
    end
  end
end
