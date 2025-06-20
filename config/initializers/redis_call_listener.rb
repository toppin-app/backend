# config/initializers/redis_call_listener.rb

# Solo lo corremos en entornos no-test
if Rails.env.development? || Rails.env.production?
  Thread.new do
    begin
      redis = Redis.new
      Rails.logger.info("[RedisCallListener] Subscribing to 'calls' Redis channel...")

      redis.subscribe("calls") do |on|
        on.message do |channel, message|
          begin
            data = JSON.parse(message)

            # Asegúrate de que receiver_id esté presente
            receiver_id = data["receiver_id"]
            if receiver_id.nil?
              Rails.logger.warn("[RedisCallListener] Missing receiver_id in payload: #{data.inspect}")
              next
            end

            # Enviamos por ActionCable
            ActionCable.server.broadcast("call_#{receiver_id}", data)
            Rails.logger.info("[RedisCallListener] Broadcasted to call_#{receiver_id}: #{data.inspect}")
          rescue => e
            Rails.logger.error("[RedisCallListener] Error processing message: #{e.message}")
          end
        end
      end
    rescue => e
      Rails.logger.error("[RedisCallListener] Redis listener failed to start: #{e.message}")
    end
  end
end
