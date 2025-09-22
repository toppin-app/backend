class BannerUser < ApplicationRecord
  belongs_to :banner
  belongs_to :user

  validates :banner_id, uniqueness: { scope: :user_id }
  
  before_create :set_viewed_at

  private

  def set_viewed_at
    self.viewed_at ||= Time.current
  end
end