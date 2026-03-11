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

  # ===== COMPLAINTS ANALYTICS =====

  def self.complaints_total(filters = {})
    scope = apply_user_filters_to_complaints(Complaint.all, filters)
    scope.count
  end

  def self.complaints_over_time(filters = {}, group_by = :week)
    scope = apply_user_filters_to_complaints(Complaint.all, filters)
    scope = apply_date_range(scope, filters, :created_at)
    case group_by
    when :day   then scope.group("DATE(complaints.created_at)").count
    when :week  then scope.group("DATE_FORMAT(DATE_SUB(complaints.created_at, INTERVAL WEEKDAY(complaints.created_at) DAY), '%Y-%m-%d')").count
    when :month then scope.group("DATE_FORMAT(complaints.created_at, '%Y-%m')").count
    end
  end

  def self.complaints_by_reporter_gender(filters = {})
    scope = apply_user_filters_to_complaints(Complaint.all, filters)
    gender_enum = User.genders
    scope.joins("INNER JOIN users AS reporters ON reporters.id = complaints.user_id")
         .group("reporters.gender")
         .count
         .transform_keys { |k| gender_enum[k.to_s] || k }
  end

  def self.complaints_by_reported_gender(filters = {})
    user_scope  = apply_filters(User.all, filters)
    user_ids    = user_scope.pluck(:id)
    to_user_ids = Complaint.where(to_user_id: user_ids).where.not(to_user_id: nil).pluck(:to_user_id)
    return {} if to_user_ids.empty?

    gender_enum  = User.genders
    counts_per_user = to_user_ids.tally
    user_genders    = User.where(id: counts_per_user.keys).pluck(:id, :gender).to_h

    distribution = {}
    counts_per_user.each do |uid, count|
      g = user_genders[uid]
      next if g.nil?
      int_key = gender_enum[g.to_s] || g.to_i
      distribution[int_key] ||= 0
      distribution[int_key] += count
    end
    distribution.sort_by { |k, _| k }.to_h
  end

  def self.complaints_gender_matrix(filters = {})
    scope = apply_user_filters_to_complaints(Complaint.all, filters)
    pairs = scope.where.not(to_user_id: nil).pluck(:user_id, :to_user_id)
    return {} if pairs.empty?

    gender_enum  = User.genders
    gender_names = { 0 => 'Mujer', 1 => 'Hombre', 2 => 'No binario', 3 => 'Pareja' }
    user_genders = User.where(id: pairs.flatten.uniq).pluck(:id, :gender).to_h

    matrix = {}
    pairs.each do |reporter_id, reported_id|
      rg_raw = user_genders[reporter_id]
      dg_raw = user_genders[reported_id]
      next if rg_raw.nil? || dg_raw.nil?

      r_int  = gender_enum[rg_raw.to_s] || rg_raw.to_i
      d_int  = gender_enum[dg_raw.to_s] || dg_raw.to_i
      r_name = gender_names[r_int] || rg_raw.to_s
      d_name = gender_names[d_int] || dg_raw.to_s

      matrix[r_name] ||= {}
      matrix[r_name][d_name] ||= 0
      matrix[r_name][d_name] += 1
    end
    matrix
  end

  def self.complaints_made_distribution(filters = {})
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)

    counts_by_user = Complaint.where(user_id: user_ids).group(:user_id).count

    distribution = {}
    user_ids.each do |uid|
      c = counts_by_user[uid] || 0
      key = c > 10 ? '>10' : c.to_s
      distribution[key] ||= 0
      distribution[key] += 1
    end

    # Return sorted 0..10, >10
    result = {}
    (0..10).each { |i| result[i.to_s] = distribution[i.to_s] || 0 }
    result['>10'] = distribution['>10'] || 0
    result
  end

  def self.complaints_received_distribution(filters = {})
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    user_ids = user_scope.pluck(:id)

    counts_by_user = Complaint.where(to_user_id: user_ids).group(:to_user_id).count

    distribution = {}
    user_ids.each do |uid|
      c = counts_by_user[uid] || 0
      key = c > 10 ? '>10' : c.to_s
      distribution[key] ||= 0
      distribution[key] += 1
    end

    result = {}
    (0..10).each { |i| result[i.to_s] = distribution[i.to_s] || 0 }
    result['>10'] = distribution['>10'] || 0
    result
  end

  def self.avg_complaints_received_by_gender(filters = {})
    user_scope = User.all
    user_scope = apply_filters(user_scope, filters)
    gender_names = { 0 => 'Mujer', 1 => 'Hombre', 2 => 'No binario', 3 => 'Pareja' }

    result = {}
    User.genders.each do |name, int_val|
      users_of_gender = user_scope.where(gender: int_val)
      total_users = users_of_gender.count
      next if total_users == 0

      user_ids = users_of_gender.pluck(:id)
      total_complaints = Complaint.where(to_user_id: user_ids).count
      label = gender_names[int_val] || name
      result[label] = (total_complaints.to_f / total_users).round(2)
    end
    result
  end

  def self.complaints_by_type_and_gender(filters = {})
    gender_names = { 0 => 'Mujer', 1 => 'Hombre', 2 => 'No binario', 3 => 'Pareja' }
    gender_enum  = User.genders
    complaint_scope = apply_user_filters_to_complaints(Complaint.all, filters)
    rows = complaint_scope.pluck(:reason, :user_id, :to_user_id)

    reporter_ids     = rows.map { |_r, uid, _t| uid }.uniq.compact
    reported_ids     = rows.map { |_r, _u, tid| tid }.uniq.compact
    reporter_genders = User.where(id: reporter_ids).pluck(:id, :gender).to_h
    reported_genders = User.where(id: reported_ids).pluck(:id, :gender).to_h

    by_type                 = {}
    by_type_reporter_gender = {}
    by_type_reported_gender = {}
    full_matrix             = {}

    rows.each do |reason, reporter_id, reported_id|
      type_label = Complaint::REASON_KEY_LABELS[reason.to_s] || reason.to_s
      # pluck(:gender) may return an Integer (MySQL) or a String enum name (Rails)
      reporter_gender_raw = reporter_genders[reporter_id]
      reported_gender_raw = reported_genders[reported_id]
      reporter_gender_int = reporter_gender_raw.nil? ? nil : (gender_enum[reporter_gender_raw.to_s] || reporter_gender_raw.to_i)
      reported_gender_int = reported_gender_raw.nil? ? nil : (gender_enum[reported_gender_raw.to_s] || reported_gender_raw.to_i)
      reporter_gender = gender_names[reporter_gender_int] || 'Desconocido'
      reported_gender = gender_names[reported_gender_int] || 'Desconocido'

      by_type[type_label] = (by_type[type_label] || 0) + 1

      by_type_reporter_gender[reporter_gender] ||= {}
      by_type_reporter_gender[reporter_gender][type_label] = (by_type_reporter_gender[reporter_gender][type_label] || 0) + 1

      by_type_reported_gender[reported_gender] ||= {}
      by_type_reported_gender[reported_gender][type_label] = (by_type_reported_gender[reported_gender][type_label] || 0) + 1

      full_matrix[reporter_gender] ||= {}
      full_matrix[reporter_gender][reported_gender] ||= {}
      full_matrix[reporter_gender][reported_gender][type_label] = (full_matrix[reporter_gender][reported_gender][type_label] || 0) + 1
    end

    {
      by_type:                 by_type,
      by_type_reporter_gender: by_type_reporter_gender,
      by_type_reported_gender: by_type_reported_gender,
      full_matrix:             full_matrix
    }
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

  def self.subscription_by_gender(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters.except(:gender, :subscription_type))
    scope = apply_date_range(scope, filters, :created_at)

    result = {}
    [['Gratuito', nil], ['Premium', 'premium'], ['Supreme', 'supreme']].each do |label, sub|
      sub_scope = sub.nil? ? scope.where(current_subscription_name: nil) : scope.where(current_subscription_name: sub)
      result[label] = sub_scope.group(:gender).count
                                 .transform_keys { |k| User.genders[k.to_s] || k }
    end
    result
  end

  def self.subscription_by_verified(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters.except(:verified, :subscription_type))
    scope = apply_date_range(scope, filters, :created_at)

    result = {}
    [['Gratuito', nil], ['Premium', 'premium'], ['Supreme', 'supreme']].each do |label, sub|
      sub_scope = sub.nil? ? scope.where(current_subscription_name: nil) : scope.where(current_subscription_name: sub)
      result[label] = {
        verified:     sub_scope.where(verified: true).count,
        non_verified: sub_scope.where(verified: false).count
      }
    end
    result
  end

  def self.verified_by_gender(filters = {})
    scope = User.all
    scope = apply_filters(scope, filters.except(:gender, :verified))
    scope = apply_date_range(scope, filters, :created_at)

    gender_to_int = ->(h) { h.transform_keys { |k| User.genders[k.to_s] || k } }
    {
      verified:     gender_to_int.call(scope.where(verified: true).group(:gender).count),
      non_verified: gender_to_int.call(scope.where(verified: false).group(:gender).count)
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

  # Restricts a Complaint scope to only complaints whose reporter (user_id) belongs
  # to the filtered user set. Intentionally ignores bot/account-status defaults so
  # that every complaint is counted regardless of the reporter's account flags —
  # only explicit contextual filters (gender, country, subscription) are applied.
  def self.apply_user_filters_to_complaints(complaint_scope, filters)
    complaint_filters = filters.except(:exclude_bots, :only_bots, :exclude_deleted, :only_deleted)
    user_scope = apply_filters(User.all, complaint_filters)
    user_ids = user_scope.pluck(:id)
    complaint_scope.where(user_id: user_ids)
  end
end
