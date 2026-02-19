class BannerUser < ApplicationRecord
  belongs_to :banner
  belongs_to :user

  # REMOVED: validates :banner_id, uniqueness: { scope: :user_id }
  # Permitir múltiples impresiones del mismo banner por usuario (como publis)
  
  before_create :set_viewed_at

  private

  def set_viewed_at
    self.viewed_at ||= Time.current
  end
end