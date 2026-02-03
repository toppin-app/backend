class AliveChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
    redis.sadd("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario conectado: #{current_user.id}")
    notify_matches_about_status_change
  end

  def unsubscribed
    redis.srem("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario desconectado: #{current_user.id}")
    notify_matches_about_status_change
  end

  # Solo notifica a los matches del usuario que cambió de estado
  def notify_matches_about_status_change
    online_user_ids = redis.smembers("online_users").map(&:to_i)
    
    # Obtener los IDs de los matches del usuario actual
    match_requests = UserMatchRequest.where(
      "(user_id = :id OR target_user = :id) AND is_match = true", 
      id: current_user.id
    )
    
    match_user_ids = match_requests.map do |mr| 
      mr.user_id == current_user.id ? mr.target_user : mr.user_id 
    end
    
    return if match_user_ids.empty?
    
    # Solo notificar a los matches que están conectados
    connected_match_ids = match_user_ids & online_user_ids
    return if connected_match_ids.empty?
    
    # Obtener todos los match_requests de los usuarios conectados en UNA sola query
    all_match_requests = UserMatchRequest.where(
      "((user_id IN (:ids) OR target_user IN (:ids)) AND is_match = true)",
      ids: connected_match_ids
    )
    
    # Agrupar por usuario
    matches_by_user = Hash.new { |h, k| h[k] = [] }
    
    all_match_requests.each do |mr|
      if connected_match_ids.include?(mr.user_id)
        matches_by_user[mr.user_id] << mr.target_user
      end
      if connected_match_ids.include?(mr.target_user)
        matches_by_user[mr.target_user] << mr.user_id
      end
    end
    
    # Obtener todos los usuarios involucrados en UNA query
    all_user_ids = matches_by_user.values.flatten.uniq
    users_hash = User.where(id: all_user_ids).select(:id, :name).index_by(&:id)
    
    # Broadcast a cada match conectado
    connected_match_ids.each do |user_id|
      match_ids = matches_by_user[user_id].uniq
      
      matches_data = match_ids.map do |match_id|
        user = users_hash[match_id]
        next unless user
        
        {
          id: user.id,
          name: user.name,
          online: online_user_ids.include?(user.id)
        }
      end.compact
      
      user = User.find_by(id: user_id)
      AliveChannel.broadcast_to(user, { type: "online_users", users: matches_data }) if user
    end
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"])
  end
end