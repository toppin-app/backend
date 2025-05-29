class UserMedium < ApplicationRecord
  belongs_to :user
  mount_base64_uploader :file, ImageUploader
  after_create :update_user

  default_scope { order(position: :asc) }

  before_create :set_position

  def set_position
    self.position = self.user.user_media.count
  end

  validate :max_user_media_limit, on: :create

  private

  def max_user_media_limit
    if user.user_media.count >= 9
      errors.add(:base, "No puedes tener más de 9 fotos en tu perfil")
    end
  end

  def update_user
      self.user.update(updated_at: DateTime.now)
  end
  
end
