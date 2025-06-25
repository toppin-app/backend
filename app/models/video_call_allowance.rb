class VideoCallAllowance < ApplicationRecord
  def self.for_pair(user_a, user_b)
    user_ids = [user_a.id, user_b.id].sort
    find_or_create_by(user_1_id: user_ids[0], user_2_id: user_ids[1]) do |record|
      record.seconds_used = 0
    end
  end

  def seconds_left
    [180 - (seconds_used || 0), 0].max
  end

  def add_seconds!(secs)
    update!(seconds_used: (seconds_used || 0) + secs)
  end
end