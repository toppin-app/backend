class UserWatchlist < ApplicationRecord
  belongs_to :user
  validates :media_type, inclusion: { in: %w[movie tv] }
end