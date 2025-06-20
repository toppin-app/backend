# app/workers/call_event_listener.rb
require 'json'

class CallEventListener
  def self.listen
    redis = Redis.new

    Thread.new do
      redis.subscribe("calls") do |on|
        on.message do |channel, msg|
          begin
            data = JSON.parse(msg)
            user_id = data["receiver_id"]
            ActionCable.server.broadcast("call_#{user_id}", data)
          rescue => e
            Rails.logger.error("Failed to process Redis message: #{e.message}")
          end
        end
      end
    end
  end
end
