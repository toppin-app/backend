class VideoCall < ApplicationRecord
  belongs_to :user_1, class_name: "User"
  belongs_to :user_2, class_name: "User"

  enum status: { pending: 0, active: 1, ended: 2 }

  scope :between, ->(u1, u2) do
    where(user_1: u1, user_2: u2).or(where(user_1: u2, user_2: u1))
  end
end
