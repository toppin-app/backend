class VideoCall < ApplicationRecord
  belongs_to :user_1, class_name: "User"
  belongs_to :user_2, class_name: "User"

  enum status: { pending: 0, active: 1, ended: 2, cancelled: 3, rejected: 4 }

  scope :between, ->(u1, u2) do
    where(user_1: u1, user_2: u2).or(where(user_1: u2, user_2: u1))
  end
  
  def self.duration(u1, u2)
    between(u1, u2).sum(:duration)
  end
  
  def calculate_duration!
  return unless ended_at && started_at

  update!(duration: (ended_at - started_at).to_i)
end
end
