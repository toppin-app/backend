class AliveChannel < ApplicationCable::Channel
  def subscribed

    stream_for current_user
    redis.sadd("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario conectado: #{current_user.id}")
    # Broadcast the updated list of online users  
    broadcast_online_users
  end

  def unsubscribed
    redis.srem("online_users", current_user.id)
    broadcast_online_users
  end

  # Método para enviar la lista de usuarios conectados a todos los clientes
  def broadcast_online_users
    user_ids = redis.smembers("online_users").map(&:to_i)
    users = User.where(id: user_ids).map do |user|
      {
        id: user.id,
        name: user.name, # o el campo que quieras mostrar
        status: "online"
      }
    end
    ActionCable.server.broadcast("alive_channel", { type: "online_users", users: users })
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"])
  end
end