class AliveChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
    redis.sadd("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario conectado: #{current_user.id}")
    # Broadcast the updated list of online users  
    alive_channel # Llama al método para enviar la lista
  end

  def unsubscribed
    redis.srem("online_users", current_user.id)
    Rails.logger.info("[AliveChannel] Usuario desconectado: #{current_user.id}")
    alive_channel # Llama al método para enviar la lista
  end

  # Método para enviar la lista de usuarios conectados a todos los clientes
  def alive_channel
    Rails.logger.info("[AliveChannel] Enviando lista de usuarios conectados")
    # Obtenemos los IDs de los usuarios conectados desde Redis
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