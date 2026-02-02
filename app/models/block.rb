class Block < ApplicationRecord
  belongs_to :user
  belongs_to :blocked_user, class_name: 'User'

  validates :user_id, presence: true
  validates :blocked_user_id, presence: true
  validates :blocked_user_id, uniqueness: { scope: :user_id, message: "ya está bloqueado" }
  
  # Evitar que un usuario se bloquee a sí mismo
  validate :cannot_block_self
  
  private
  
  def cannot_block_self
    if user_id == blocked_user_id
      errors.add(:blocked_user_id, "no puedes bloquearte a ti mismo")
    end
  end
end
