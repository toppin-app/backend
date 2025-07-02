class AliveChannel < ApplicationCable::Channel
  def subscribed
    stream_from "alive_channel"
    redis.sadd("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario conectado: #{current_user.id}")
    alive_channel
  end

  def unsubscribed
    redis.srem("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario desconectado: #{current_user.id}")
    alive_channel # Notifica a todos los usuarios
  end

  # Método para enviar la lista de usuarios conectados a todos los clientes
  def alive_channel
    Rails.logger.info("[AliveChannel] Enviando lista de matches conectados")
    user_ids = redis.smembers("online_users").map(&:to_i)

    User.find_each do |user|
      # Obtener matches del usuario (bidireccional)
      match_requests = UserMatchRequest.where("(user_id = :id OR target_user = :id) AND is_match = true", id: user.id)
      match_user_ids = match_requests.map { |mr| mr.user_id == user.id ? mr.target_user : mr.user_id }
      matches = User.where(id: match_user_ids)

      matches_data = matches.map do |match|
        {
          id: match.id,
          name: match.name,
          online: user_ids.include?(match.id)
        }
      end

      # Notificar solo al usuario actual su lista de matches y su estado online
      AliveChannel.broadcast_to(user, { type: "online_matches", matches: matches_data })
    end
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"])
  end
end