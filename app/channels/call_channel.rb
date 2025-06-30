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
  def ping(data)
    if data.dig("message", "type") == "call_status_report"
      channel_name = data["channel_name"]
      status = data["message"]["status"] # true (activa) o false (finalizada)
      user_id = current_user.id

      # Guarda el último ping de este usuario en Redis
      redis.setex("#{REDIS_KEY_PREFIX}:#{channel_name}:#{user_id}", TIMEOUT_SECONDS, Time.now.to_i)

      call = VideoCall.find_by(agora_channel_name: channel_name, status: [:active, :pending])

      # Si la llamada sigue activa y status es false, la finalizamos
      if call && status == false
        end_call_and_notify(call, channel_name, "status_report")
        return
      end

      # Comprobar si el otro usuario lleva más de TIMEOUT_SECONDS sin enviar ping
      if call
        other_user_id = [call.user_1_id, call.user_2_id].find { |id| id != user_id }
        last_ping = redis.get("#{REDIS_KEY_PREFIX}:#{channel_name}:#{other_user_id}")
        if last_ping.nil? || Time.now.to_i - last_ping.to_i > TIMEOUT_SECONDS
          end_call_and_notify(call, channel_name, "timeout")
        end
      end

      return
    end
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