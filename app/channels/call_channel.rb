class CallChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_user
    stream_for current_user
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end