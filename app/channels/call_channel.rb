class CallChannel < ApplicationCable::Channel
  REDIS_KEY_PREFIX = "call_ping".freeze
  TIMEOUT_SECONDS = 10

  def subscribed
    stream_for current_user
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  # Recibe el ping del frontend con el estado de ambos usuarios
  # def ping(data)
  #   ...existing code...
  # end
  # Ahora el método se llama call_status_report y es el que debe invocar el frontend
  def call_status_report(data)
    status = data.dig("message", "status") # true (activa) o false (finalizada)
    user_id = current_user.id

    # Buscar la llamada activa o pendiente del usuario actual
    call = VideoCall.where(status: [:active, :pending])
                   .where("user_1_id = ? OR user_2_id = ?", user_id, user_id)
                   .order(created_at: :desc)
                   .first

    unless call
      Rails.logger.warn("[CallChannel] No active/pending call found for user_id=#{user_id}")
      Rails.logger.warn("[CallChannel] Data recibido: #{data.inspect}")
      return
    end

    channel_name = call.agora_channel_name
    Rails.logger.info("[CallChannel] Procesando ping para call_id=#{call.id}, channel_name=#{channel_name}, user_id=#{user_id}, status=#{status}")

    # Guarda el último ping de este usuario en Redis
    redis.setex("#{REDIS_KEY_PREFIX}:#{channel_name}:#{user_id}", TIMEOUT_SECONDS, Time.now.to_i)

    # Si la llamada sigue activa y status es false, la finalizamos
    if status == false || status == "false" || status == 0
      Rails.logger.info("[CallChannel] Finalizando llamada por status_report para call_id=#{call.id}, user_id=#{user_id}")
      end_call_and_notify(call, channel_name, "status_report")
      return
    end

    # Comprobar si el otro usuario lleva más de TIMEOUT_SECONDS sin enviar ping
    other_user_id = [call.user_1_id, call.user_2_id].find { |id| id != user_id }
    last_ping = redis.get("#{REDIS_KEY_PREFIX}:#{channel_name}:#{other_user_id}")
    Rails.logger.info("[CallChannel] last_ping del otro usuario (user_id=#{other_user_id}): #{last_ping}")
    if last_ping.nil? || Time.now.to_i - last_ping.to_i > TIMEOUT_SECONDS
      Rails.logger.info("[CallChannel] Finalizando llamada por timeout para call_id=#{call.id}, user_id=#{user_id}")
      end_call_and_notify(call, channel_name, "timeout")
    end

    return
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"])
  end

  def end_call_and_notify(call, channel_name, reason)
    ended_at = Time.current
    duration = call.started_at ? (ended_at - call.started_at).to_i : 0
    call.update!(status: :ended, ended_at: ended_at, duration: duration)
    [call.user_1_id, call.user_2_id].each do |uid|
      CallChannel.broadcast_to(User.find(uid), {
        message: {
          type: "call_ended",
          reason: reason,
          channel_name: channel_name
        }
      })
    end
  end
end