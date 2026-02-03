class AliveChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
    redis.sadd("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario conectado: #{current_user.id}")
    alive_channel
  end

  def unsubscribed
    redis.srem("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario desconectado: #{current_user.id}")
    alive_channel
  end

  # Notifica a cada usuario su propia lista de matches y su estado online
  def alive_channel
    Rails.logger.info("[AliveChannel] Enviando lista de matches conectados")
    user_ids = redis.smembers("online_users").map(&:to_i)
    
    # Solo procesar usuarios que están conectados
    return if user_ids.empty?

    User.where(id: user_ids).find_each do |user|
      match_requests = UserMatchRequest.where("(user_id = :id OR target_user = :id) AND is_match = true", id: user.id)
      match_user_ids = match_requests.map { |mr| mr.user_id == user.id ? mr.target_user : mr.user_id }
      matches = User.where(id: match_user_ids)

      matches_data = matches.map do |match|
        {
          id: match.id,
          name: match.name,
          online: user_ids.include?(match.id) # true si está online, false si no
        }
      end

      # Si quieres que también salga el propio usuario en la lista, añade aquí:
      # matches_data << { id: user.id, name: user.name, online: user_ids.include?(user.id) }

      AliveChannel.broadcast_to(user, { type: "online_users", users: matches_data })
    end
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"])
  end
end