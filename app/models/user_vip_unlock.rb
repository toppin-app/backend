class UserVipUnlock < ApplicationRecord
  belongs_to :user
  validates :user_id, uniqueness: { scope: :target_id }
end
